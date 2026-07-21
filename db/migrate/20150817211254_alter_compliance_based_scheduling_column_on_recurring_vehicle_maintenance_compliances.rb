class AlterComplianceBasedSchedulingColumnOnRecurringVehicleMaintenanceCompliances < ActiveRecord::Migration[4.2]
  def up
    change_column_default :recurring_vehicle_maintenance_compliances, :compliance_based_scheduling, false
  end

  def down
    change_column_default :recurring_vehicle_maintenance_compliances, :compliance_based_scheduling, nil
  end
end