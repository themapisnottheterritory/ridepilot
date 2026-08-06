class RunEtaWorker
  include Sidekiq::Worker
  sidekiq_options queue: 'default', retry: 1

  # Recompute live GPS-based ETAs for a run's remaining pickups. Enqueued by
  # AvlPollerWorker after a fresh position lands, so ETAs refresh every poll.
  def perform(run_id)
    RunEtaEstimator.update_for(run_id)
  end
end
