class AddTransferRuleToProviders < ActiveRecord::Migration[7.1]
  # Transfer policy decided 2026-09-10: 90 minutes, different route only. A
  # second tap on the same route inside the window (a ride home) pays again.
  def change
    add_column :providers, :fare_transfer_different_route_only, :boolean, null: false, default: true
  end
end
