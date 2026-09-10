class SplitPassDiscounts < ActiveRecord::Migration[7.1]
  # The proposed prepay table discounts the 10-ride and 20-ride passes
  # differently (10% and 20%), so one shared setting is not enough.
  def change
    rename_column :providers, :fare_multi_trip_discount_pct, :fare_pass_10_discount_pct
    add_column :providers, :fare_pass_20_discount_pct, :integer, null: false, default: 0
  end
end
