class AddDirectionToRepeatingTrips < ActiveRecord::Migration[4.2]
  def change
    add_column :repeating_trips, :direction, :string, default: :outbound
    remove_column :repeating_trips, :round_trip, :boolean
  end
end
