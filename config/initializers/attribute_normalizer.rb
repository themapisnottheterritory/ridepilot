AttributeNormalizer.configure do |config|
  config.normalizers[:titleize] = lambda do |value, options|
    (value.is_a?(String) && value.size > 0) ? (value[0].upcase + value[1..-1]) : value
  end

  config.normalizers[:upcase] = lambda do |value, options|
    value.is_a?(String) ? value.upcase : value
  end

  config.normalizers[:squish] = lambda do |value, options|
    value.is_a?(String) ? value.strip.gsub(/\s+/, ' ') : value
  end
end

# Include AttributeNormalizer after models are loaded (for Zeitwerk compatibility)
Rails.application.config.to_prepare do
  ApplicationRecord.send :include, AttributeNormalizer
end
