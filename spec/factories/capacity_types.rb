FactoryBot.define do
  factory :capacity_type do
    name { Faker::Lorem.words(number: 2).join(' ') }
    provider { nil }
  end

end
