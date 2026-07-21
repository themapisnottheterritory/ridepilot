class FleetOptimizerService
  OPTIMIZER_URL = ENV.fetch("OPTIMIZER_URL", "http://localhost:8765")
  PICKUP_SLACK_BEFORE = 5.minutes.to_i
  PICKUP_SLACK_AFTER  = 10.minutes.to_i

  def self.optimize_fleet(provider, date)
    new(provider, date).call
  end

  def initialize(provider, date)
    @provider = provider
    @date = date
  end

  def call
    runs = @provider.runs.for_date(@date).not_cancelled
                    .includes(:vehicle, :from_garage_address, trips: [:pickup_address, :dropoff_address, :ridership_mobilities])
    return { "error" => "No runs for date" } if runs.empty?

    payload = build_payload(runs)
    return { "error" => "No trips to optimize" } if payload[:trips].empty?

    uri = URI("#{OPTIMIZER_URL}/optimize/fleet")
    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = 60

    request = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
    request.body = payload.to_json

    response = http.request(request)
    raise "Optimizer HTTP #{response.code}: #{response.body}" unless response.code == "200"

    result = JSON.parse(response.body)
    apply_result(result) if result["solver_status"] == "success"
    result
  end

  private

  def build_payload(runs)
    vehicles = runs.filter_map { |run| serialize_vehicle(run) }
    trips = runs.flat_map(&:trips).filter_map { |t| serialize_trip(t) }

    {
      provider_id: @provider.id,
      date: @date.to_s,
      vehicles: vehicles,
      trips: trips
    }
  end

  def serialize_vehicle(run)
    depot = run.from_garage_address || run.vehicle&.garage_address
    return nil unless depot&.latitude && run.vehicle

    {
      run_id: run.id,
      capacity_seats: run.vehicle.seating_capacity || 8,
      capacity_tie_downs: run.vehicle.mobility_device_accommodations || 2,
      depot_lat: depot.latitude.to_f,
      depot_lng: depot.longitude.to_f,
      earliest_start: seconds_from_midnight(run.scheduled_start_time),
      latest_end: seconds_from_midnight(run.scheduled_end_time)
    }
  end

  def serialize_trip(trip)
    return nil unless trip.pickup_address&.latitude && trip.dropoff_address&.latitude
    return nil unless trip.pickup_time

    pickup_local = trip.pickup_time.in_time_zone(timezone)
    midnight = pickup_local.beginning_of_day
    pickup_seconds = (pickup_local - midnight).to_i

    {
      trip_id: trip.id,
      pickup_lat: trip.pickup_address.latitude.to_f,
      pickup_lng: trip.pickup_address.longitude.to_f,
      dropoff_lat: trip.dropoff_address.latitude.to_f,
      dropoff_lng: trip.dropoff_address.longitude.to_f,
      earliest_pickup: [pickup_seconds - PICKUP_SLACK_BEFORE, 0].max,
      latest_pickup: [pickup_seconds + PICKUP_SLACK_AFTER, 86399].min,
      seats: trip_seat_count(trip),
      tie_downs: trip_tiedown_count(trip)
    }
  end

  def apply_result(result)
    midnight = @date.in_time_zone(timezone).beginning_of_day

    # Group assignments by run_id
    by_run = result["assignments"].group_by { |a| a["run_id"] }

    ActiveRecord::Base.transaction do
      by_run.each do |run_id, assignments|
        run = Run.find(run_id)

        manifest_order = ["run_begin"]
        assignments.sort_by { |a| a["position"] }.each do |assignment|
          trip_id = assignment["trip_id"]
          eta_time = midnight + assignment["eta"].seconds

          Trip.where(id: trip_id).update_all(
            run_id: run_id,
            estimated_pickup_time: eta_time
          )

          manifest_order << "trip_#{trip_id}_leg_1"
          manifest_order << "trip_#{trip_id}_leg_2"
        end
        manifest_order << "run_end"

        run.manifest_order = manifest_order
        run.manifest_changed = true
        run.save(validate: false)
        run.reset_itineraries
      end
    end
  end

  def seconds_from_midnight(time)
    return 0 unless time
    local = time.in_time_zone(timezone)
    (local - local.beginning_of_day).to_i
  end

  def trip_seat_count(trip)
    count = trip.customer_space_count.to_i
    count > 0 ? count : 1
  end

  def trip_tiedown_count(trip)
    return 0 unless trip.ridership_mobilities.has_capacity.any?

    wheelchair_ids = CapacityType.where("lower(name) LIKE ?", "%wheelchair%")
                                 .or(CapacityType.where("lower(name) LIKE ?", "%tie%down%"))
                                 .pluck(:id)
    return 0 if wheelchair_ids.empty?

    total = 0
    trip.ridership_mobilities.has_capacity.each do |rm|
      mc = MobilityCapacity.where(host_id: rm.mobility_id, capacity_type_id: wheelchair_ids)
                           .where("capacity > 0")
      total += rm.capacity * mc.sum(:capacity) if mc.any?
    end
    total
  end

  def timezone
    "Central Time (US & Canada)"
  end
end
