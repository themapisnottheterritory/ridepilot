class AddWheelchairLiftToVehicles < ActiveRecord::Migration[7.1]
  # A real lift flag (ops/fleet-sync-plan.md). accessibility_equipment stays
  # as free text for everything else. Backfilled from that text, which is
  # how the 41 Aerotech / Champion Defender units were recorded on 2026-09-10.
  def up
    add_column :vehicles, :wheelchair_lift, :boolean, null: false, default: false
    execute "UPDATE vehicles SET wheelchair_lift = TRUE WHERE accessibility_equipment ILIKE '%wheelchair lift%'"
  end

  def down
    remove_column :vehicles, :wheelchair_lift
  end
end
