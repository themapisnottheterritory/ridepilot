class AddMobilityDeviceAccommodationsToTrips < ActiveRecord::Migration[4.2]
  def change
    add_column :trips, :mobility_device_accommodations, :integer
  end
end
