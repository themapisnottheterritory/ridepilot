class OvernightOptimizeJob < ApplicationJob
  queue_as :optimizer

  def perform(date = Date.tomorrow)
    date = Date.parse(date.to_s) unless date.is_a?(Date)

    # Phase 1: Optimize each run individually
    Run.for_date(date).not_cancelled.each do |run|
      next if run.trips.count < 2
      RouteOptimizeJob.perform_later(run.id)
    end

    # Phase 2: Cross-run fleet optimization per provider
    provider_ids = Run.for_date(date).not_cancelled
                      .joins(:trips)
                      .distinct
                      .pluck(:provider_id)
                      .uniq

    provider_ids.each do |provider_id|
      FleetOptimizeJob.perform_later(provider_id, date.to_s)
    end

    # Send morning ETA window SMS after optimization completes
    SendEtaWindowNotificationsJob.perform_later(date.to_s)
  end
end
