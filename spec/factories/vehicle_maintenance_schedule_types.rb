FactoryBot.define do
  factory :vehicle_maintenance_schedule_type do
    name { Faker::Lorem.words(number: 2).join(' ') }
    provider
  end

end
