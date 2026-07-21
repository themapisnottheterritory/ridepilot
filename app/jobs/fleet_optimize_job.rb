class FleetOptimizeJob < ApplicationJob
  queue_as :optimizer

  def perform(provider_id, date)
    provider = Provider.find(provider_id)
    date = Date.parse(date.to_s) unless date.is_a?(Date)
    result = FleetOptimizerService.optimize_fleet(provider, date)
    Rails.logger.info("Fleet optimization for provider #{provider_id} on #{date}: #{result['solver_status']}")
    result
  end
end
