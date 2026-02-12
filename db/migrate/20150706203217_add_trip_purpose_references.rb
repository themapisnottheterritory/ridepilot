class AddTripPurposeReferences < ActiveRecord::Migration[4.2]
  def change
    add_reference :trips, :trip_purpose, index: true
    add_reference :repeating_trips, :trip_purpose, index: true
    add_reference :addresses, :trip_purpose, index: true
  end
end
