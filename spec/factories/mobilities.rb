require 'faker'

FactoryBot.define do
  factory :mobility do
    sequence(:name) { |n| "sample_mobility_#{n}" }  # name is unique
  end
end
