FactoryBot.define do
  factory :fare do
    fare_type { :free }

    trait :donation do
      fare_type { :donation }
    end

    trait :payment do
      fare_type { :payment }
    end
  end
end
