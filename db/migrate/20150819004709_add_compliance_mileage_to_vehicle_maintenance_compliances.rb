class AddComplianceMileageToVehicleMaintenanceCompliances < ActiveRecord::Migration[4.2]
  def change
    add_column :vehicle_maintenance_compliances, :compliance_mileage, :integer
  end
end
