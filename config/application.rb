require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Ridepilot
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 5.0


    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w(assets tasks))

    # The distance/duration services live in app/services/distance_duration_services/
    # but are referenced by their bare class names (e.g. OsrmDistanceDurationService
    # in TripDistanceDurationProxy). Collapse the directory so Zeitwerk treats those
    # files as top-level constants instead of expecting a DistanceDurationServices::
    # namespace (which otherwise raises "uninitialized constant").
    Rails.autoloaders.main.collapse("#{root}/app/services/distance_duration_services")

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
