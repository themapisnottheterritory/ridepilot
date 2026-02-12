FactoryBot.define do
  factory :custom_report do
    title { Faker::Lorem.words(number: 2).join(' ') }
    name { Faker::Lorem.words(number: 2).join(' ') }
    redirect_to_results { false }
  end

end
