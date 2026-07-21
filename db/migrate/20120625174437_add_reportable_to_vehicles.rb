class AddReportableToVehicles < ActiveRecord::Migration[4.2]
  def self.up
    add_column :vehicles, :reportable, :boolean
    Vehicle.update_all :reportable => true
  end

  def self.down
    remove_column :vehicles, :reportable
  end
end
