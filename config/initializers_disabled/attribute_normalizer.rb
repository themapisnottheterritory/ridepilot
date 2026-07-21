require 'attribute_normalizer'  # Ensure the gem is loaded
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

ApplicationRecord.send :include, AttributeNormalizer
