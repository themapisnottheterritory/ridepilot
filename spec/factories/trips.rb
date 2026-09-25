FactoryBot.define do
  factory :trip do
    association :pickup_address, factory: :address
    association :dropoff_address, factory: :address
    pickup_time { (Time.current - 1.week).beginning_of_day }
    appointment_time { pickup_time + 30.minutes }
    trip_purpose
    customer
    provider { customer ? customer.provider : association(:provider) }

    factory :cab_trip do
      cab { true }
    end

    trait :complete do
      after(:build) do |trip|
        trip.appointment_time = Time.current
        trip.trip_result = create :trip_result, code: "COMP"
      end
    end

    trait :turned_down do
      after(:build) do |trip|
        trip.trip_result = create :trip_result, code: "TD"
      end
    end
  end
end
