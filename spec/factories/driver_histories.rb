FactoryBot.define do
  factory :driver_history do
    driver
    event { Faker::Lorem.words(number: 2).join(' ') }
    event_date { Date.current }
  end
end
