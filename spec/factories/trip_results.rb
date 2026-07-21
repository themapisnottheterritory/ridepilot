FactoryBot.define do
  factory :trip_result do
    code { Faker::Lorem.words(number: 2).join(' ') }
    name { Faker::Lorem.words(number: 2).join(' ') }
    description { "result_description" }
  end

end
