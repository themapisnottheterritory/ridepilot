FactoryBot.define do
  factory :verification_question do
    question { Faker::Lorem.words(number: 5).join(' ') + '?' }
    answer { Faker::Lorem.words(number: 2).join(' ') }
    user
  end

end
