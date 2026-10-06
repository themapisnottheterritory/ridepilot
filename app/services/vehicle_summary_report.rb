# Vehicle Summary (Goliad, 2026-10-06): for each bus over a date range, the
# revenue and non-revenue hours and miles, from what the driver recorded. Kept
# the way NTD counts demand response: revenue service runs from the first
# pick-up to the last drop-off, empty legs between riders included; the trips
# from the garage and back to it are non-revenue.
#
#   hours: the run's start and end on the tablet (actual_start_time and
#          actual_end_time); revenue = first stop reached to last stop done
#   miles: end odometer - start odometer; non-revenue = road distance (our
#          OSRM, kept a month on disk) from the garage to the first stop and
#          from the last stop back;
#          revenue = the rest
#
# A run counts only when it has both odometer readings, a start and an end on
# the tablet, at least one stop done and a garage that fits (the drive from it
# and back is under 3/4 of the odometer miles). Runs short of that are
# listed with what is missing, so they can be closed out. Runs with no trips
# and nothing recorded are left out. (The older Vehicle Monthly Service Report
# estimates miles from the planned route and can exceed the odometer.)
class VehicleSummaryReport
  MAX_RUN_MILES = 1000   # odometer readings further apart than this are a typo
  # Garage legs this large a share of the odometer mean the garage on file is
  # not where the bus starts (bus R9 on the Matagorda runs, garaged on file in
  # Victoria: 136 miles of garage legs on a 54-mile run, 2026-10-02). The rule
  # lives in GarageFit, with the nightly check and the bus's page.
  MAX_GARAGE_SHARE = GarageFit::MAX_GARAGE_SHARE

  RunRow = Struct.new(:run, :vehicle, :driver, :start_at, :first_stop_at, :last_stop_at, :end_at,
                      :odometer_miles, :deadhead_out, :deadhead_in, :trips, :passengers, :missing, keyword_init: true) do
    def counted?
      missing.empty?
    end

    def total_hours
      (end_at - start_at) / 3600.0
    end

    def revenue_hours
      (last_stop_at - first_stop_at) / 3600.0
    end

    def non_revenue_hours
      total_hours - revenue_hours
    end

    # never more than the odometer says the bus went
    def non_revenue_miles
      [deadhead_out.to_f + deadhead_in.to_f, odometer_miles.to_f].min
    end

    def revenue_miles
      odometer_miles.to_f - non_revenue_miles
    end
  end

  TOTAL_KEYS = %i[runs total_hours revenue_hours non_revenue_hours total_miles revenue_miles non_revenue_miles trips passengers].freeze

  attr_reader :rows, :empty_runs

  # distance: optional ->(from_address, to_address) { miles } (specs)
  def initialize(provider_ids:, start_date:, end_date:, vehicle_id: nil, distance: nil)
    @provider_ids = provider_ids
    @start_date = start_date
    @end_date = end_date
    @vehicle_id = vehicle_id
    @distance = distance || method(:road_miles)
    @rows = []
    @empty_runs = 0
  end

  def run!
    runs = Run.where(provider_id: @provider_ids).for_date_range(@start_date, @end_date).today_and_prior
              .where.not(vehicle_id: nil)
              .includes(:from_garage_address, :to_garage_address, vehicle: :garage_address, driver: :user)
              .order(:date, :name)
    runs = runs.where(vehicle_id: @vehicle_id) if @vehicle_id
    runs = runs.to_a
    ids = runs.map(&:id)

    stops = Itinerary.where(run_id: ids, leg_flag: [1, 2]).includes(:address).group_by(&:run_id)
    trips = Trip.where(run_id: ids).completed.group_by(&:run_id)
    any_trip = Trip.where(run_id: ids).distinct.pluck(:run_id).to_set

    runs.each do |run|
      recorded = run.start_odometer || run.end_odometer || run.actual_start_time || run.actual_end_time
      unless any_trip.include?(run.id) || recorded
        @empty_runs += 1
        next
      end
      @rows << build_row(run, stops[run.id] || [], trips[run.id] || [])
    end
    self
  end

  def counted
    @rows.select(&:counted?)
  end

  def not_counted
    @rows.reject(&:counted?)
  end

  # [{ vehicle:, runs:, total_hours:, ... }], by vehicle name
  def by_vehicle
    counted.group_by(&:vehicle).map { |vehicle, rs| totals_for(rs).merge(vehicle: vehicle) }
           .sort_by { |h| h[:vehicle].to_s }
  end

  def totals
    totals_for(counted)
  end

  private

  def totals_for(rs)
    {
      runs: rs.size,
      total_hours: rs.sum(&:total_hours), revenue_hours: rs.sum(&:revenue_hours), non_revenue_hours: rs.sum(&:non_revenue_hours),
      total_miles: rs.sum { |r| r.odometer_miles.to_f }, revenue_miles: rs.sum(&:revenue_miles), non_revenue_miles: rs.sum(&:non_revenue_miles),
      trips: rs.sum(&:trips), passengers: rs.sum(&:passengers)
    }
  end

  def build_row(run, stops, done_trips)
    missing = []
    reached = stops.select { |s| s.arrival_time || s.finish_time }
    first = reached.min_by { |s| s.arrival_time || s.finish_time }
    last = reached.max_by { |s| s.finish_time || s.arrival_time }
    first_at = first && (first.arrival_time || first.finish_time)
    last_at = last && (last.finish_time || last.arrival_time)

    if run.start_odometer.nil? || run.end_odometer.nil?
      missing << (run.start_odometer || run.end_odometer ? "one odometer reading" : "odometer readings")
    elsif run.end_odometer < run.start_odometer || run.end_odometer - run.start_odometer > MAX_RUN_MILES
      missing << "odometer readings that add up (#{run.start_odometer} to #{run.end_odometer})"
    end
    missing << "a start on the tablet" unless run.actual_start_time
    missing << "an end on the tablet (not closed out)" unless run.actual_end_time
    missing << "a stop marked done" unless first_at

    from_garage, to_garage = GarageFit.garages(run)
    missing << "a garage on the run or the bus" unless from_garage && to_garage

    out_miles = in_miles = nil
    if missing.empty?
      out_miles = @distance.call(from_garage, first.address)
      in_miles = @distance.call(last.address, to_garage)
      if out_miles.nil? || in_miles.nil?
        missing << "a road distance from the garage (map lookup failed)"
      elsif !GarageFit.legs_fit?(legs = out_miles + in_miles, run.end_odometer - run.start_odometer)
        missing << "a garage that fits this run (from #{from_garage.address_text} to the first stop and back is " \
                   "#{legs.round} miles; the odometer shows #{run.end_odometer - run.start_odometer})"
      end
    end

    RunRow.new(
      run: run, vehicle: run.vehicle&.name, driver: run.driver&.user_name,
      start_at: [run.actual_start_time, first_at].compact.min,
      first_stop_at: first_at, last_stop_at: last_at,
      end_at: [run.actual_end_time, last_at].compact.max,
      odometer_miles: (run.end_odometer - run.start_odometer if run.start_odometer && run.end_odometer),
      deadhead_out: out_miles, deadhead_in: in_miles,
      trips: done_trips.size, passengers: done_trips.sum(&:human_trip_size),
      missing: missing
    )
  end

  # Driving miles by road on our OSRM server, remembered for the request and
  # kept a month on disk (garage-to-stop pairs repeat run after run). The app's
  # own Rails.cache is a NullStore here, so it has its own small file store.
  ROAD_MEMORY = ActiveSupport::Cache::FileStore.new(Rails.root.join("tmp", "cache", "vehicle-summary-road-miles"))

  def road_miles(from, to)
    return nil unless from&.latitude && from&.longitude && to&.latitude && to&.longitude
    key = [from.latitude, from.longitude, to.latitude, to.longitude].map { |c| c.to_f.round(5) }
    @road ||= {}
    return @road[key] if @road.key?(key)
    @road[key] = ROAD_MEMORY.fetch(key.join(","), expires_in: 30.days, skip_nil: true) do
      TripDistanceDurationProxy.new("OSRM", from_lat: key[0], from_lon: key[1], to_lat: key[2], to_lon: key[3],
                                            trip_datetime: Time.current).get_drive_distance
    end
  rescue StandardError => e
    Rails.logger.warn "VehicleSummaryReport road_miles: #{e.class}: #{e.message}"
    nil
  end
end
