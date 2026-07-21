FactoryBot.define do
  factory :ada_question do
    name  { Faker::Lorem.words(number: 2).join(' ') }
  end

end
