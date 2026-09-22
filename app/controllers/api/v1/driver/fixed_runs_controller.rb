# GCRPC Driver (the fixed-route turn-by-turn tablet app) collects fare-card
# taps against a RidePilot fixed run, but it knows routes by their GTFS ids,
# not RidePilot's, and nobody schedules its runs in the office. This opens the
# run the taps will land on: today's fixed run for this driver on the route
# whose external ids include the GTFS route, created if it does not exist.
#
#   POST /api/v1/fixed_runs/open   { external_route_id, vehicle?, scheduled_start?, scheduled_end?, run_name? }
#
# Idempotent: the same driver on the same route the same day gets the same
# run back while it is open, so a tablet restart mid-run keeps counting on the
# one sheet. A run that has been ended (post-trip done, end odometer in) stays
# ended; a second pull-out on the same route the same day gets a new run.
# The run is not *started* here: the tablet starts it (runs/:id/start) with the
# odometer from the pre-trip inspection, the same order Demand Response uses.
# Availability rules are not applied (like runs#start, which also saves
# without validation): a driver on a bus with riders at the door is not the
# moment to refuse a fare because dispatch double-booked them.
#
# The answer carries everything the tablet needs for a tap: the run id, the
# route's stops with their external ids (the tablet matches its own stop ids
# to them), rider categories and fare types for cash counts, and the sheet
# so far (boardings_payload) so a restarted tablet shows today's numbers.
class Api::V1::Driver::FixedRunsController < Api::V1::Driver::BaseController
  include Api::FixedRouteJson

  def open
    ext = params[:external_route_id].to_s.strip
    return render fail_response(status: 422, external_route_id: "external_route_id is required.") if ext.blank?
    provider = @driver.provider
    route = FixedRoute.for_provider(provider.id).active.where("? = ANY(external_route_ids)", ext).first
    return render fail_response(status: 404, code: "unknown_route", route: "RidePilot has no fixed route for #{ext}.") unless route

    date = Time.zone.today
    run = Run.where(provider: provider, driver: @driver, fixed_route: route, date: date, service_mode: "fixed_route")
             .where(deleted_at: nil, actual_end_time: nil).order(:id).last
    created = false
    if run.nil?
      run = Run.new(provider: provider, driver: @driver, fixed_route: route, date: date, service_mode: "fixed_route",
                    name: params[:run_name].presence || "#{route.display_name} · #{@driver.user&.display_name || @driver.user&.username}")
      run.scheduled_start_time = parse_clock(date, params[:scheduled_start])
      run.scheduled_end_time   = parse_clock(date, params[:scheduled_end]) || (run.scheduled_start_time && run.scheduled_start_time + 2.hours)
      created = true
    end
    if params[:vehicle].present?
      vehicle = Vehicle.where(provider: provider, deleted_at: nil).find_by(name: params[:vehicle].to_s.strip)
      run.vehicle = vehicle if vehicle
    end
    run.save(validate: false)
    reports = VehicleInspectionReport.where(run_id: run.id).where.not(submitted_at: nil)

    render success_response(boardings_payload(run).merge(
      created: created,
      stops: route.stops.map { |s|
        { id: s.id, external_route_id: s.external_route_id, external_stop_id: s.external_stop_id,
          name: s.name, direction: s.direction, sequence: s.sequence }
      },
      rider_categories: RiderCategory.by_provider(provider).default_order.map(&:as_api_json),
      fare_types: FareType.by_provider(provider).default_order.map(&:as_api_json),
      vehicle: run.vehicle&.name,
      vehicle_id: run.vehicle_id,
      started: run.actual_start_time.present?,
      start_odometer: run.start_odometer,
      pre_inspection_done: reports.where(phase: "pre").exists?,
      post_inspection_done: reports.where(phase: "post").exists?
    ))
  end

  private

  def parse_clock(date, hhmm)
    return nil if hhmm.blank?
    m = hhmm.to_s.match(/\A(\d{1,2}):(\d{2})/) or return nil
    Time.zone.local(date.year, date.month, date.day, m[1].to_i % 24, m[2].to_i)
  rescue ArgumentError
    nil
  end
end
