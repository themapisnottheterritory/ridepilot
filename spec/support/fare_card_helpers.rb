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

# A fixed-route run for tap specs: route with two stops, the usual rider
# categories and fare types, driven by the given driver today.
module FareTapHelpers
  def build_fixed_run(provider, driver: nil)
    driver ||= create(:driver, provider: provider)
    route = FixedRoute.create!(provider: provider, name: "Red", color: "FF0000")
    FixedRouteStop.create!(fixed_route: route, external_route_id: "r1", external_stop_id: "s1", direction: "East", sequence: 1, name: "Depot")
    FixedRouteStop.create!(fixed_route: route, external_route_id: "r1", external_stop_id: "s2", direction: "East", sequence: 2, name: "Mall")
    RiderCategory.find_or_create_by!(name: "Adult") { |c| c.default_fare = 1.00 }
    RiderCategory.find_or_create_by!(name: "Senior") { |c| c.default_fare = 0.50 }
    FareType.find_or_create_by!(name: "Cash") { |f| f.fare_factor = 1 }
    FareType.find_or_create_by!(name: "Pass") { |f| f.fare_factor = 0 }
    FareType.find_or_create_by!(name: "Free / Transfer") { |f| f.fare_factor = 0 }
    FareType.find_or_create_by!(name: "Card") { |f| f.fare_factor = 1 }
    # The vehicle factory predates Rails 7's required belongs_to too.
    vehicle = build(:vehicle, provider: provider)
    vehicle.save!(validate: false)
    run = create(:run, provider: provider, driver: driver, vehicle: vehicle, service_mode: "fixed_route", fixed_route_id: route.id)
    [run, driver, route]
  end
end

RSpec.configure do |config|
  config.include FareTapHelpers
end

# A demand-response trip for the rider on a run driven today by the driver,
# with the provider set to collect a payment fare at pickup.
module FareTripHelpers
  def build_udr_trip(provider, rider, driver: nil, fare_amount: nil)
    driver ||= create(:driver, provider: provider)
    provider.fare ||= Fare.create!(fare_type: :payment, pre_trip: true)
    provider.fare.update!(fare_type: :payment, pre_trip: true)
    provider.save!(validate: false)
    vehicle = build(:vehicle, provider: provider)
    vehicle.save!(validate: false)
    run = create(:run, provider: provider, driver: driver, vehicle: vehicle)
    trip = build(:trip, provider: provider, customer: rider, run: run, pickup_time: Time.current, appointment_time: Time.current + 30.minutes, fare_amount: fare_amount)
    trip.save!(validate: false)
    [trip, run, driver]
  end
end

RSpec.configure do |config|
  config.include FareTripHelpers
end
