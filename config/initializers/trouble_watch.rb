# Errors and slow pages for the trouble board (TroubleWatch).
ActiveSupport::Notifications.subscribe("process_action.action_controller") do |*args|
  TroubleWatch.action_processed(ActiveSupport::Notifications::Event.new(*args))
rescue StandardError => e
  Rails.logger.warn("TroubleWatch: #{e.class}: #{e.message}")
end
