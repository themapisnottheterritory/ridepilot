# Fixed-route compliance: one row per fixed run in a date range, built from
# what the tablet filed (stop visits, boardings, DVIR reports) and the run
# itself. The rule being checked is transit's own: the bus stops and dwells
# at every published stop, leaves no timepoint early, and the driver inspects
# the bus before and after. Anything short of that shows up in `issues`.
class FixedRouteCompliance
  EARLY_S = 30      # departed this much before the published time = early (same line as the tablet)
  LATE_S  = 300     # this much after = late

  Row = Struct.new(:run, :date, :run_name, :route_name, :driver_name, :vehicle_name,
                   :started_at, :ended_at, :start_odometer, :end_odometer, :miles,
                   :trips, :stops_served, :stops_skipped, :early, :late, :avg_dwell,
                   :boarded, :fares, :pre_trip, :post_trip, :unsafe, :defects,
                   :skipped_list, :early_list, :issues, keyword_init: true)

  def initialize(provider_id, start_date:, end_date:, fixed_route_id: nil, driver_id: nil, vehicle_id: nil)
    @provider_id = provider_id
    @start_date, @end_date = start_date, end_date
    @fixed_route_id, @driver_id, @vehicle_id = fixed_route_id, driver_id, vehicle_id
  end

  def runs
    scope = Run.where(provider_id: @provider_id, service_mode: "fixed_route", deleted_at: nil)
               .where("runs.date >= ? and runs.date < ?", @start_date, @end_date)
               .includes(:fixed_route, :vehicle, driver: :user)
    scope = scope.where(fixed_route_id: @fixed_route_id) if @fixed_route_id
    scope = scope.where(driver_id: @driver_id) if @driver_id
    scope = scope.where(vehicle_id: @vehicle_id) if @vehicle_id
    scope.order(:date, :scheduled_start_time, :id).to_a
  end

  def rows
    rs = runs
    ids = rs.map(&:id)
    visits    = FixedRouteStopVisit.where(run_id: ids).to_a.group_by(&:run_id)
    boardings = FixedRouteBoarding.where(run_id: ids).to_a.group_by(&:run_id)
    reports   = VehicleInspectionReport.where(run_id: ids).where.not(submitted_at: nil).to_a.group_by(&:run_id)

    rs.map do |run|
      v = visits[run.id] || []
      b = boardings[run.id] || []
      r = reports[run.id] || []
      served  = v.select { |x| x.status == "served" }
      skipped = v.select { |x| x.status == "skipped" }
      early   = v.select { |x| x.deviation_seconds && x.deviation_seconds < -EARLY_S }
      late    = v.select { |x| x.deviation_seconds && x.deviation_seconds > LATE_S }
      dwell   = served.map(&:dwell_seconds).compact
      pre  = r.find { |x| x.phase == "pre" }
      post = r.find { |x| x.phase == "post" }
      unsafe = r.any? { |x| x.safe_to_operate == false }
      defects = r.sum { |x| x.run_vehicle_inspections.count { |li| li.status == "defect" } }
      miles = run.start_odometer && run.end_odometer ? run.end_odometer - run.start_odometer : nil

      issues = []
      issues << "no pre-trip" unless pre
      issues << "no post-trip" unless post || run.actual_end_time.nil?   # a run still out has no post-trip yet
      issues << "not ended" if run.actual_start_time && run.actual_end_time.nil? && run.date < Time.zone.today
      issues << "#{skipped.size} skipped" if skipped.any?
      issues << "#{early.size} early" if early.any?
      issues << "unsafe" if unsafe
      issues << "no stop data" if v.empty? && run.actual_start_time

      Row.new(
        run: run, date: run.date, run_name: run.name, route_name: run.fixed_route&.display_name || "(no route)",
        driver_name: run.driver&.user_name || "(none)", vehicle_name: run.vehicle&.name || "(none)",
        started_at: run.actual_start_time, ended_at: run.actual_end_time,
        start_odometer: run.start_odometer, end_odometer: run.end_odometer, miles: miles,
        trips: v.map(&:trip_id).compact.uniq.size,
        stops_served: served.size, stops_skipped: skipped.size, early: early.size, late: late.size,
        avg_dwell: dwell.any? ? (dwell.sum.to_f / dwell.size).round : nil,
        boarded: b.sum(&:boarded_count), fares: b.sum { |x| x.fare_amount.to_f },
        pre_trip: pre, post_trip: post, unsafe: unsafe, defects: defects,
        skipped_list: skipped.sort_by { |x| [x.trip_id.to_s, x.sequence.to_i] }.map { |x|
          { trip: x.trip_id, stop: x.stop_name, scheduled: x.scheduled_time&.strftime("%H:%M"), passed: x.departed_at || x.arrived_at } },
        early_list: early.sort_by { |x| [x.trip_id.to_s, x.sequence.to_i] }.map { |x|
          { trip: x.trip_id, stop: x.stop_name, scheduled: x.scheduled_time&.strftime("%H:%M"), left: x.departed_at, minutes: (-x.deviation_seconds / 60.0).round(1) } },
        issues: issues
      )
    end
  end

  def totals(rows)
    published = rows.sum { |r| r.stops_served + r.stops_skipped }
    { runs: rows.size, trips: rows.sum(&:trips), served: rows.sum(&:stops_served), skipped: rows.sum(&:stops_skipped),
      skip_rate: published > 0 ? (100.0 * rows.sum(&:stops_skipped) / published).round(1) : nil,
      early: rows.sum(&:early), late: rows.sum(&:late), boarded: rows.sum(&:boarded), fares: rows.sum(&:fares),
      miles: rows.sum { |r| r.miles.to_i },
      no_pre: rows.count { |r| !r.pre_trip }, no_post: rows.count { |r| r.issues.include?("no post-trip") },
      unsafe: rows.count(&:unsafe), clean: rows.count { |r| r.issues.empty? },
      days: rows.map(&:date).uniq.size }
  end
end
