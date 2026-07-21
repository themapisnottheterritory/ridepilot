FactoryBot.define do
  factory :vehicle do
    name { Faker::Lorem.words(number: 2).join(' ') }
    provider
    seating_capacity { 10 }
    mobility_device_accommodations { 2 }
  end
end
