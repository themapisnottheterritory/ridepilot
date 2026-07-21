require 'faker'

FactoryBot.define do
  factory :region do
    name  { Faker::Lorem.words(number: 2).join(' ') }
  end
end
