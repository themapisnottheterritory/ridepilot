FactoryBot.define do
  factory :vehicle_warranty do
    vehicle
    description { Faker::Lorem.words(number: 2).join(' ') }
    expiration_date { Date.current.tomorrow }
  end
end
