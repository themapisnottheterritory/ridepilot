class ChangeVehiclesAddDefaultDriverId < ActiveRecord::Migration[4.2]
  def self.up
    add_column :vehicles, :default_driver_id, :integer
  end

  def self.down
    remove_column :vehicles, :default_driver_id
  end
end
