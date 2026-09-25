require 'faker'

FactoryBot.define do
  factory :funding_source do
    sequence(:name) { |n| "sample_funding_source_#{n}" }
  end
end
