FactoryBot.define do
  factory :vehicle_maintenance_compliance do
    vehicle
    event { Faker::Lorem.words(number: 2).join(' ') }
    due_type { "date" }
    due_date { Date.current.tomorrow }
    
    trait :complete do
      compliance_date { Date.current }
      compliance_mileage { 123 }
    end

    trait :recurring do
      after(:build) do |vmc|
        vmc.recurring_vehicle_maintenance_compliance = create :recurring_vehicle_maintenance_compliance, provider: vmc.vehicle.provider
      end
    end
  end
end
