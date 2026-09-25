require 'faker'

FactoryBot.define do
  factory :customer do
    first_name { Faker::Name.first_name }
    last_name { Faker::Name.last_name }
    provider
    # belongs_to is required in every environment (the initializer that sets
    # belongs_to_required_by_default = false runs too late to take effect), so
    # a customer needs these to save, exactly as the form supplies them.
    mobility
    service_level
    association :default_funding_source, factory: :funding_source
    association :address, factory: :customer_common_address
    
    trait :with_travel_trainings do
      after(:create) do |customer|
        3.times { create(:travel_training, customer: customer) }
      end
    end

    trait :with_funding_authorization_numbers do
      after(:create) do |customer|
        3.times { create(:funding_authorization_number, customer: customer) }
      end
    end
  end
end
