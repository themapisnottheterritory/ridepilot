require 'faker'

FactoryBot.define do
  factory :funding_source do
    name  { Faker::Lorem.words(number: 2).join(' ') }
  end
end
