class AddInitialMileageChangeReasonToVehicles < ActiveRecord::Migration[4.2]
  def change
    add_column :vehicles, :initial_mileage_change_reason, :text
  end
end
