class AddVehicleMaintenanceScheduleIdToVehicleMaintenanceCompliances < ActiveRecord::Migration[4.2]
  def change
    add_column :vehicle_maintenance_compliances, :vehicle_maintenance_schedule_id, :integer
    add_index :vehicle_maintenance_compliances, :vehicle_maintenance_schedule_id, name: 'index_compl_veh_maint_sched_id'

  end
end
