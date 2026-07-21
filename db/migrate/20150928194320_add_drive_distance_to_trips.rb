class AddDriveDistanceToTrips < ActiveRecord::Migration[4.2]
  def change
    add_column :trips, :drive_distance, :float
  end
end
