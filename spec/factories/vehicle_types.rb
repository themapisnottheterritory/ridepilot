FactoryBot.define do
  factory :vehicle_type do
    name { Faker::Lorem.words(number: 2).join(' ') }
    provider 
  end

end
