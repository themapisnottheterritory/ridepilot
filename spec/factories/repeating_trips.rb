FactoryBot.define do
  factory :repeating_trip do
    association :pickup_address, factory: :address
    association :dropoff_address, factory: :address
    pickup_time { Time.now + 1.week }
    appointment_time { pickup_time + 30.minutes }
    provider
    customer
    trip_purpose

    # SCHEDULE ATTRS
    start_date { Time.zone.today } # Set the schedule start date to equal date field
    repetition_interval { 1 }   # Setting this messes up the recurring_ride_coordinator shared examples 
    repeats_mondays { start_date.monday? }
    repeats_tuesdays { start_date.tuesday? }
    repeats_wednesdays { start_date.wednesday? }
    repeats_thursdays { start_date.thursday? }
    repeats_fridays { start_date.friday? }
    repeats_saturdays { start_date.saturday? }
    repeats_sundays { start_date.sunday? }
  end
end
