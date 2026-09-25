FactoryBot.define do
  factory :address_group do
    sequence(:name) { |n| "sample_address_group_#{n}" }  # name is unique
  end

end
