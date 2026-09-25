FactoryBot.define do
  factory :vehicle_type do
    sequence(:name) { |n| "sample_vehicle_type_#{n}" }  # unique within a provider
    provider 
  end

end
