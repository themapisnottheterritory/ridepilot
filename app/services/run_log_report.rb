# Shelby's "Vehicle Summary Report" layout (2026-10-08, from her spreadsheet
# ~/ridepilot-ops/RidePilot Reporting Layouts.xlsx on .16): one row per run,
# grouped by mode (UDR, Rural Demand Response, Commuter, Fixed Route), then by
# date, then driver. Her formulas, which are how NTD counts demand response:
#
#   revenue time  = last drop-off - first pick-up
#   revenue miles = last drop-off odometer - first pick-up odometer
#   deadhead time = (first pick-up - start of shift) + (end of shift - last drop-off)
#   deadhead miles, the same with odometers
#
# Drivers enter the odometer at the start and end of the shift only, so the
# odometer at the first pick-up and the last drop-off is worked out: the
# bus's GPS miles from the start of the shift to the first pick-up (and from
# the last drop-off to the end) when the bus reports GPS, otherwise the road
# distance from the garage, as the Vehicle Summary does. Each row says which.
#
# PMT (passenger miles, Shelby's NTD question): for demand response, each
# completed trip's road miles pick-up to drop-off (trips.drive_distance) times
# its riders (the rider, guests and attendants, as NTD counts them). Average
# trip length = PMT / UPT. Fixed-route PMT needs boardings, which aren't
# counted yet.
class RunLogReport
  MODES = ["UDR", "Rural Demand Response", "Commuter", "Fixed Route"].freeze
  MAX_RUN_MILES = VehicleSummaryReport::MAX_RUN_MILES

  Row = Struct.new(:mode, :run_id, :date, :driver, :route, :bus, :start_at, :first_pickup_at, :last_dropoff_at, :end_at,
                   :start_odo, :first_pickup_odo, :last_dropoff_odo, :end_odo, :miles_by, :lunch_in, :lunch_out,
                   :upt, :pmt, :notes, :revenue_miles_direct, :deadhead_miles_direct, keyword_init: true) do
    def revenue_hours = hours(first_pickup_at, last_dropoff_at)

    def deadhead_hours
      a, b = hours(start_at, first_pickup_at), hours(last_dropoff_at, end_at)
      a && b ? (a + b).round(2) : nil
    end

    def revenue_miles
      revenue_miles_direct || diff(first_pickup_odo, last_dropoff_odo)
    end

    def deadhead_miles
      return deadhead_miles_direct if deadhead_miles_direct
      a, b = diff(start_odo, first_pickup_odo), diff(last_dropoff_odo, end_odo)
      a && b ? (a + b).round(1) : nil
    end

    def complete?
      [start_at, first_pickup_at, last_dropoff_at, end_at, revenue_miles, deadhead_miles].all?
    end

    private

    def hours(a, b) = (a && b && b >= a ? ((b - a) / 3600.0).round(2) : nil)
    def diff(a, b) = (a && b && b >= a ? (b - a).round(1) : nil)
  end

  attr_reader :rows, :commuter_without_data

  # A finished day is kept on disk and built again only when one of its runs,
  # stops or trips changes. ops cron builds yesterday each night, so the
  # report opens without waiting on GPS.
  MEMORY = ActiveSupport::Cache::FileStore.new(Rails.root.join("tmp", "cache", "run-log"))
  VERSION = 3   # bump when the rows are worked out differently

  # gps: GpsMiles-like (#miles(unit, from, to)); road: ->(from_addr, to_addr) { miles }
  def initialize(provider_ids:, start_date:, end_date:, gps: nil, road: nil, compare: nil)
    @provider_ids = Array(provider_ids)
    @start_date, @end_date = start_date, end_date
    @gps = gps
    @road = road
    @compare = compare || FixedRouteRows.fetcher
    @rows = []
  end

  def run!
    @commuter_without_data = 0
    # one agency at a time, so the days the nightly job built are used
    @provider_ids.each do |pid|
      one = self.class.new(provider_ids: [pid], start_date: @start_date, end_date: @end_date, gps: @gps, road: @road, compare: @compare)
      (@start_date...@end_date).each do |day|
        next if day > Date.current
        # kept only once the day is over and the nightly GPS build has covered it
        keep = day < Date.current && gps_built_through.to_s >= day.to_s
        built = keep ? MEMORY.fetch(one.send(:day_key, day), expires_in: 400.days) { one.send(:build_day, day) } : one.send(:build_day, day)
        @rows.concat(built[:rows])
        @commuter_without_data += built[:commuter_without_data]
      end
    end
    @rows.sort_by! { |r| [MODES.index(r.mode) || 9, r.date, r.driver.to_s.downcase, r.route.to_s, r.first_pickup_at || r.start_at || r.date.in_time_zone] }
    self
  end

  # The last day the published-vs-driven build has GPS trips for (its 07:15 run
  # covers yesterday). A day after that would be kept without its fixed-route
  # and commuter rows.
  def gps_built_through
    @gps_built_through ||= Array(@compare.call("index.json")).map { |r| r["until"].to_s }.max
  end

  def self.build_day!(provider_ids, day, **opts)
    r = new(provider_ids: provider_ids, start_date: day, end_date: day + 1, **opts)
    MEMORY.write(r.send(:day_key, day), r.send(:build_day, day), expires_in: 400.days)
  end

  private

  def day_key(day)
    runs = Run.where(provider_id: @provider_ids, date: day)
    ids = runs.pluck(:id)
    stamp = [runs.maximum(:updated_at), Itinerary.where(run_id: ids).maximum(:updated_at), Trip.where(run_id: ids).maximum(:updated_at)].compact.max
    "v#{VERSION}/#{@provider_ids.sort.join('-')}/#{day}/#{ids.size}/#{stamp&.strftime('%s%6N')}"
  end

  def build_day(day)
    rows = []
    runs = Run.where(provider_id: @provider_ids, date: day).where(cancelled: [nil, false])
              .includes(:provider, :vehicle, :fixed_route, :from_garage_address, :to_garage_address, driver: :user)
              .order(:date, :name).to_a
    dr = runs.select { |r| r.service_mode == "demand_response" }
    ids = dr.map(&:id)
    stops = Itinerary.where(run_id: ids, leg_flag: [1, 2]).includes(:address).group_by(&:run_id)
    done = Trip.where(run_id: ids).completed.group_by(&:run_id)
    any = Trip.where(run_id: ids).distinct.pluck(:run_id).to_set
    dr.each do |run|
      recorded = run.start_odometer || run.end_odometer || run.actual_start_time || run.actual_end_time
      next unless any.include?(run.id) || recorded
      rows << dr_row(run, stops[run.id] || [], done[run.id] || [])
    end
    fixed = FixedRouteRows.new(runs.select { |r| r.service_mode == "fixed_route" }, day, day + 1, gps: @gps, compare: @compare)
    rows.concat(fixed.rows)
    { rows: rows, commuter_without_data: fixed.commuter_without_data }
  end

  public

  def by_mode
    MODES.map { |m| [m, @rows.select { |r| r.mode == m }] }.reject { |_, rs| rs.empty? }
  end

  def totals(rows)
    sum = ->(f) { rows.filter_map(&f).sum.round(2) }
    upt = rows.sum { |r| r.upt.to_i }
    pmt_rows = rows.select(&:pmt)
    pmt = pmt_rows.sum(&:pmt).round(1)
    pmt_upt = pmt_rows.sum { |r| r.upt.to_i }
    { runs: rows.size, complete: rows.count(&:complete?), upt: upt,
      pmt: pmt_rows.any? ? pmt : nil, aptl: pmt_upt.positive? ? (pmt / pmt_upt).round(2) : nil,
      revenue_hours: sum.(:revenue_hours), revenue_miles: sum.(:revenue_miles),
      deadhead_hours: sum.(:deadhead_hours), deadhead_miles: sum.(:deadhead_miles) }
  end

  def self.mode_for_run(run)
    return (run.fixed_route&.kind == "commuter" ? "Commuter" : "Fixed Route") if run.service_mode == "fixed_route"
    run.name.to_s.match?(/\AUDR/i) ? "UDR" : "Rural Demand Response"
  end

  private

  def dr_row(run, stops, done)
    notes = []
    reached = stops.select { |s| s.arrival_time || s.finish_time }
    first = reached.min_by { |s| s.arrival_time || s.finish_time }
    last = reached.max_by { |s| s.finish_time || s.arrival_time }
    first_at = first && (first.arrival_time || first.finish_time)
    last_at = last && (last.finish_time || last.arrival_time)
    start_at, end_at = run.actual_start_time, run.actual_end_time
    if start_at && first_at && start_at > first_at
      notes << "Started on the tablet after the first pick-up"
      start_at = first_at
    end
    if end_at && last_at && end_at < last_at
      notes << "Ended on the tablet before the last drop-off"
      end_at = last_at
    end

    start_odo, end_odo = run.start_odometer, run.end_odometer
    if start_odo && end_odo && (end_odo < start_odo || end_odo - start_odo > MAX_RUN_MILES)
      notes << "Odometer readings don't add up (#{start_odo} to #{end_odo})"
      start_odo = end_odo = nil
    end
    notes << "No start of shift on the tablet" unless start_at
    notes << "Not closed out on the tablet" unless end_at
    notes << "No start odometer" unless run.start_odometer
    notes << "No end odometer" if run.end_odometer.nil? && end_at
    notes << "No stop marked done" unless first_at

    unit = run.vehicle&.name
    out = gps_or_road(unit, start_at, first_at) { from_garage(run) && first && road(from_garage(run), first.address) }
    back = gps_or_road(unit, last_at, end_at) { to_garage(run) && last && road(last.address, to_garage(run)) }
    rev = gps_miles(unit, first_at, last_at)

    fp = start_odo && out[:miles] ? (start_odo + out[:miles]).round(1) : nil
    ld = end_odo && back[:miles] ? (end_odo - back[:miles]).round(1) : nil
    ld ||= (fp + rev).round(1) if fp && rev
    fp ||= (ld - rev).round(1) if ld && rev
    if fp && ld && ld < fp
      notes << "GPS and odometer readings disagree"
      fp = ld = nil
    end
    by = [out[:by], back[:by]].compact.uniq
    if fp || ld
      notes << (by == [:gps] ? "Pick-up and drop-off odometers from GPS" : by.include?(:road) ? "Pick-up and drop-off odometers estimated by road from the garage" : nil)
    end
    notes << run.driver_notes.to_s.strip if run.driver_notes.present?
    notes << run.uncomplete_reason.to_s.strip if run.uncomplete_reason.present?

    Row.new(mode: self.class.mode_for_run(run), run_id: run.id, date: run.date, driver: run.driver&.user_name,
            route: run.name, bus: unit, start_at: start_at, first_pickup_at: first_at, last_dropoff_at: last_at,
            end_at: end_at, start_odo: start_odo, first_pickup_odo: fp, last_dropoff_odo: ld, end_odo: end_odo,
            miles_by: by, upt: done.sum(&:human_trip_size),
            pmt: done.sum { |t| t.drive_distance.to_f * t.human_trip_size }.round(1), notes: notes.compact.uniq)
  end

  def gps_or_road(unit, from, to)
    if (m = gps_miles(unit, from, to))
      { miles: m, by: :gps }
    elsif (m = yield)
      { miles: m.round(1), by: :road }
    else
      { miles: nil, by: nil }
    end
  end

  def gps_miles(unit, from, to)
    @gps&.miles(unit, from, to)
  end

  def road(from, to)
    (@road || ->(a, b) { (@vs ||= VehicleSummaryReport.new(provider_ids: @provider_ids, start_date: @start_date, end_date: @end_date)).send(:road_miles, a, b) }).call(from, to)
  end

  def from_garage(run) = GarageFit.garages(run).first
  def to_garage(run) = GarageFit.garages(run).last
end
