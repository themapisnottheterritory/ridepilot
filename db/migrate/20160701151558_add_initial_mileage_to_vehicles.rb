class AddInitialMileageToVehicles < ActiveRecord::Migration[4.2]
  def change
    add_column :vehicles, :initial_mileage, :integer, default: 0
  end
end
