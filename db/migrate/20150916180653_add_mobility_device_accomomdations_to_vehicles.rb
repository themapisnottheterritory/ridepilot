class AddMobilityDeviceAccomomdationsToVehicles < ActiveRecord::Migration[4.2]
  def change
    add_column :vehicles, :mobility_device_accommodations, :integer
  end
end
