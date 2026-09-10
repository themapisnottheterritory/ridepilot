# The customer factory predates Rails 7's required belongs_to and cannot be
# created on its own in the test DB; fare card specs build a rider with the
# associations Customer now insists on.
module FareCardHelpers
  def create_rider(provider, attrs = {})
    create(:customer, {
      provider: provider,
      address: create(:customer_common_address),
      mobility: Mobility.first || create(:mobility),
      default_funding_source: create(:funding_source, provider_id: provider.id),
      service_level: ServiceLevel.first || create(:service_level)
    }.merge(attrs))
  end
end

RSpec.configure do |config|
  config.include FareCardHelpers
end
