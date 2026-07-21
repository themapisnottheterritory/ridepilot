# DVIR step 2 — guard so a report's defects are pushed into vehicle_maintenance_events
# only once (idempotent re-submit). Additive + reversible.
class AddMaintenancePushedAtToVehicleInspectionReports < ActiveRecord::Migration[7.1]
  def change
    add_column :vehicle_inspection_reports, :maintenance_pushed_at, :datetime
  end
end
