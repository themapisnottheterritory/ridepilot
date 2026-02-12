class AddVehicleTypeToVehicles < ActiveRecord::Migration[4.2]
  def change
    add_reference :vehicles, :vehicle_type, index: true
  end
end
