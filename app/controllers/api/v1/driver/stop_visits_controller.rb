# Which published stops the bus actually stopped at (GCRPC Fixed Route).
#
#   POST /api/v1/runs/:id/stop_visits   { visits: [{ client_uuid, external_route_id, external_stop_id,
#                                          trip_id, stop_name, direction, sequence, status, scheduled_time,
#                                          arrived_at, departed_at, dwell_seconds, deviation_seconds,
#                                          latitude, longitude }, ...] }
#   GET  /api/v1/runs/:id/stop_visits   today's rows for this run
#
# Batched and idempotent on client_uuid: the tablet posts what it has every
# minute or so and again after a gap in signal, and a row that already landed
# is simply counted as accepted.
class Api::V1::Driver::StopVisitsController < Api::V1::Driver::BaseController
  include Api::FixedRouteJson
  before_action :load_fixed_run

  def create
    rows = Array(params[:visits])
    return render fail_response(status: 422, visits: "visits is required.") if rows.empty?
    stops = @run.fixed_route.stops.index_by { |s| [s.external_route_id, s.external_stop_id] }
    accepted = 0
    rows.each do |v|
      uuid = v[:client_uuid].to_s.strip
      next if uuid.blank? || FixedRouteStopVisit.exists?(client_uuid: uuid)
      stop = stops[[v[:external_route_id].to_s, v[:external_stop_id].to_s]]
      FixedRouteStopVisit.create!(
        provider: @run.provider, run: @run, fixed_route: @run.fixed_route, fixed_route_stop: stop,
        external_route_id: v[:external_route_id].to_s, external_stop_id: v[:external_stop_id].to_s,
        trip_id: v[:trip_id].presence, stop_name: v[:stop_name].presence || stop&.name,
        direction: v[:direction].presence || stop&.direction, sequence: v[:sequence].presence&.to_i || stop&.sequence,
        status: FixedRouteStopVisit::STATUSES.include?(v[:status].to_s) ? v[:status].to_s : "served",
        scheduled_time: v[:scheduled_time].presence, arrived_at: v[:arrived_at].presence, departed_at: v[:departed_at].presence,
        dwell_seconds: v[:dwell_seconds].presence&.to_i, deviation_seconds: v[:deviation_seconds].presence&.to_i,
        latitude: v[:latitude].presence, longitude: v[:longitude].presence, client_uuid: uuid
      )
      accepted += 1
    end
    render success_response(run_id: @run.id, accepted: accepted, total: @run.fixed_route_stop_visits.count)
  rescue ActiveRecord::RecordInvalid => e
    render fail_response(status: 422, visits: e.message)
  end

  def index
    rows = @run.fixed_route_stop_visits.chronological
    render success_response(run_id: @run.id, visits: rows.map { |r| r.slice(:id, :external_route_id, :external_stop_id, :trip_id, :stop_name, :direction, :sequence, :status, :scheduled_time, :arrived_at, :departed_at, :dwell_seconds, :deviation_seconds) })
  end
end
