require 'faker'

FactoryBot.define do
  factory :provider do
    sequence(:name) {|n| "sample_provider_#{n}" }
    advance_day_scheduling { 21 }
    cab_enabled { true }
    fare
    association :business_address, factory: :provider_business_address
    association :mailing_address, factory: :provider_mailing_address
  end
end
