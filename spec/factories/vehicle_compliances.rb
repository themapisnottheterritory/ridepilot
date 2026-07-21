FactoryBot.define do
  factory :vehicle_compliance do
    vehicle 
    vehicle_requirement_template
    event { Faker::Lorem.words(number: 2).join(' ') }
    due_date { Date.current.tomorrow }
    
    trait :complete do
      compliance_date { Date.current }
    end
  end

end
