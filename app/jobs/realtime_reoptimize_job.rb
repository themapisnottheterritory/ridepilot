class RealtimeReoptimizeJob < ApplicationJob
  queue_as :high_critical

  def perform(run_id, completed_trip_ids: [])
    run = Run.find(run_id)
    remaining_trips = run.trips.where.not(id: completed_trip_ids)
    return if remaining_trips.count < 2

    result = RouteOptimizerService.new(run).call

    return unless result.is_a?(Hash) && result["solver_status"] == "success"

    # Broadcast updated ETAs to dispatch view and any client portal subscribers
    broadcast_data = {
      ordered_trip_ids: result["ordered_trip_ids"],
      etas: result["etas"],
      updated_at: Time.current.iso8601
    }

    # Include driver GPS if available from gps_locations
    latest_gps = GpsLocation.where(run_id: run_id).order(log_time: :desc).first
    if latest_gps
      broadcast_data[:driver_lat] = latest_gps.latitude
      broadcast_data[:driver_lng] = latest_gps.longitude
    end

    ActionCable.server.broadcast("run_eta_#{run_id}", broadcast_data)
  end
end
