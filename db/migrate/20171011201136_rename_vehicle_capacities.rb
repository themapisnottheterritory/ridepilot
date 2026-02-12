class RenameVehicleCapacities < ActiveRecord::Migration[4.2]
  def change
    rename_table :vehicle_capacities, :capacities
    rename_column :capacities, :vehicle_type_id, :host_id
    add_column :capacities, :type, :string
  end
end
