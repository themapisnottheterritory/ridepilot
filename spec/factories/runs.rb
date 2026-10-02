FactoryBot.define do
  factory :run do
    sequence(:name) { |n| "Sample Run #{n}" }  # unique per provider and date
    vehicle
    driver
    provider
    today
    
    trait :child_run do
      repeating_run
    end

    trait :scheduled_morning do
      scheduled_start_time { "9:00 AM" }
      scheduled_end_time { "11:00 AM" }
    end
    
    trait :scheduled_afternoon do
      scheduled_start_time { "1:00 PM" }
      scheduled_end_time { "3:00 PM" }
    end

    trait :completed do
      scheduled_morning
      start_odometer { 100 }
      end_odometer { 200 }
      complete { true }
    end

    trait :last_week do
      date { Time.zone.today - 1.week }
    end

    trait :two_days_ago do
      date { Time.zone.today - 2.days }
    end

    trait :yesterday do
      date { Date.yesterday }
    end

    trait :today do
      date { Time.zone.today }
    end

    trait :tomorrow do
      date { Date.tomorrow }
    end

    trait :next_week do
      date { Time.zone.today + 1.week }
    end

  end
end
