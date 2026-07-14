# DVIR step 4 (Phase 1, G1) — flag vehicles equipped with air brakes so the
# inspection template shows air-brake-only items (Air Compressor, Air/Low-Air
# Warning, Slack Adjuster) for those vehicles. Additive + reversible.
class AddAirBrakeToVehicles < ActiveRecord::Migration[7.1]
  def change
    add_column :vehicles, :air_brake, :boolean, default: false, null: false
  end
end
