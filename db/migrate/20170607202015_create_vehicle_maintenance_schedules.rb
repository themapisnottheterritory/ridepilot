class CreateVehicleMaintenanceSchedules < ActiveRecord::Migration[4.2]
  def change
    create_table :vehicle_maintenance_schedules do |t|
      t.string :name
      t.integer :mileage
      t.references :vehicle_maintenance_schedule_type

      t.timestamps
    end

    add_index :vehicle_maintenance_schedules, :vehicle_maintenance_schedule_type_id, :name => :index_vehicle_maintenance_schedule_type_id
  end
end
