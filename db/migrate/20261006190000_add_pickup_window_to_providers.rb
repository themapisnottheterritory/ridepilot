# The pick-up window and no-show rules (PickupWindow), set per agency.
# Defaults: a 0/+30 window (FTA allows up to 30 minutes in all), a 5-minute
# wait from when the window opens, and up to 15 minutes early for a rider who
# has agreed to an early pick-up.
class AddPickupWindowToProviders < ActiveRecord::Migration[7.1]
  def change
    add_column :providers, :pickup_window_early_min, :integer, default: 0, null: false
    add_column :providers, :pickup_window_late_min, :integer, default: 30, null: false
    add_column :providers, :no_show_wait_min, :integer, default: 5, null: false
    add_column :providers, :early_boarding_min, :integer, default: 15, null: false
  end
end
