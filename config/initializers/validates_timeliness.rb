begin
  require 'validates_timeliness'

  ValidatesTimeliness.setup do |config|
    # Default timezone
    config.default_timezone = Rails.application.config.time_zone

    # Other configurations can be uncommented if needed
    # config.use_plugin_parser = false
    # config.parser.add_formats()
    # config.parser.remove_formats()
  end
rescue LoadError => e
  # ValidatesTimeliness not available
  puts "ValidatesTimeliness not available: #{e.message}"
end