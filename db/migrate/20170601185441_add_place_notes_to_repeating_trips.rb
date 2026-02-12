class AddPlaceNotesToRepeatingTrips < ActiveRecord::Migration[4.2]
  def change
    add_column :repeating_trips, :pickup_address_notes, :string
    add_column :repeating_trips, :dropoff_address_notes, :string
  end
end
