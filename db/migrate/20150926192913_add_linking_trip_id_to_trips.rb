class AddLinkingTripIdToTrips < ActiveRecord::Migration[4.2]
  def change
    add_column :trips, :linking_trip_id, :integer
    add_index :trips, :linking_trip_id
  end
end
