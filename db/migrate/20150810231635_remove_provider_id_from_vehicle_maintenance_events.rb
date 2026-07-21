class RemoveProviderIdFromVehicleMaintenanceEvents < ActiveRecord::Migration[4.2]
  def change
    remove_index :vehicle_maintenance_events, :provider_id
    remove_column :vehicle_maintenance_events, :provider_id, null: true
    change_column :vehicle_maintenance_events, :vehicle_id, :integer, null: true
  end
end