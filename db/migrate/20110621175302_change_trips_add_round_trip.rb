class ChangeTripsAddRoundTrip < ActiveRecord::Migration[4.2]
  def self.up
    add_column :trips, :round_trip, :boolean
  end

  def self.down
    remove_column :trips, :round_trip
  end
end
