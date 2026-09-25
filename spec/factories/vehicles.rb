FactoryBot.define do
  factory :vehicle do
    sequence(:name) { |n| "Sample Vehicle #{n}" }  # unique within a provider
    provider
    # belongs_to is required in every environment; the fleet form always sets a type.
    vehicle_type { provider ? association(:vehicle_type, provider: provider) : nil }
    # Begin/end run legs are itineraries at the garage; without one they fail to save.
    garage_address { provider ? association(:garage_address, provider: provider) : nil }
    seating_capacity { 10 }
    mobility_device_accommodations { 2 }
  end
end
