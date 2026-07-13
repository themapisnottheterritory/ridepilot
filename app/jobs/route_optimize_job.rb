class RouteOptimizeJob < ApplicationJob
  queue_as :optimizer
  retry_on StandardError, wait: 30.seconds, attempts: 3

  def perform(run_id)
    run = Run.find(run_id)
    result = RouteOptimizerService.optimize_run(run)
    Rails.logger.info("Route optimization for run #{run_id}: #{result['solver_status']}")
    result
  end
end
