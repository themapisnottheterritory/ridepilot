FactoryBot.define do
  factory :funding_authorization_number do
    customer
    number { Faker::Number.number(digits: 10).to_s }  # string column
    funding_source
    contact_info { Faker::Lorem.words(number: 12).join(' ') }
  end

end
