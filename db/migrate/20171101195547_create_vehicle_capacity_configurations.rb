class CreateVehicleCapacityConfigurations < ActiveRecord::Migration[4.2]
  def change
    create_table :vehicle_capacity_configurations do |t|
      t.references :vehicle_type, index: true

      t.timestamps
    end
  end
end
