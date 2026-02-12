class AddOccupancyFieldsToRepeatingTrips < ActiveRecord::Migration[4.2]
  def change
    add_column :repeating_trips, :customer_space_count, :integer
    add_column :repeating_trips, :service_animal_space_count, :integer
  end
end
