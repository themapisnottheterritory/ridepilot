require 'faker'

# Note that every once in a while we may randomly generate two drivers with the
# same name, which will cause spec to fail.
FactoryBot.define do
  factory :driver do
    name { Faker::Lorem.words(number: 3).join(' ') }
    provider
    user
    association :address, factory: :driver_address
    phone_number { '(801)4567890' }
  end
end
