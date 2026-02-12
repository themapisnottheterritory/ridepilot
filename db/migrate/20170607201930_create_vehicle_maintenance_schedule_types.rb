class CreateVehicleMaintenanceScheduleTypes < ActiveRecord::Migration[4.2]
  def change
    create_table :vehicle_maintenance_schedule_types do |t|
      t.string :name

      t.timestamps
    end
  end
end
