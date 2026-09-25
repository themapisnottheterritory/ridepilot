FactoryBot.define do
  factory :service_level do
    sequence(:name) { |n| "sample_service_level_#{n}" }  # name is unique
  end

end
