require 'faker'

FactoryBot.define do
  factory :ethnicity do
    name  { Faker::Lorem.words(number: 2).join(' ') }
  end
end
