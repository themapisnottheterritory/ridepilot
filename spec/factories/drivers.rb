require 'faker'

FactoryBot.define do
  factory :driver do
    sequence(:name) { |n| "Sample Driver #{n}" }
    provider
    user
    association :address, factory: :driver_address
    phone_number { '(801)4567890' }
  end
end
