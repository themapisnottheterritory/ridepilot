FactoryBot.define do
  factory :saved_custom_report do
    name  { Faker::Lorem.words(number: 5).join(' ') }
    custom_report 
    provider 
    date_range_type { 1 }
    report_params { "MyText" }
  end

end
