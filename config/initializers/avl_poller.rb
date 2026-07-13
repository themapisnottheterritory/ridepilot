begin
  require 'sidekiq'

  Sidekiq.configure_server do |config|
    config.on(:startup) do
      # Start the AVL poller if any provider has external AVL enabled (either source)
      if Provider.where(use_external_avl: true).exists?
        Rails.logger.info "AvlPoller: Starting AVL polling..."
        AvlPollerWorker.perform_async
      end
    end
  end
rescue LoadError
  # Sidekiq not available
end
