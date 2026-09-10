class AddReducedMonthlyPassPrice < ActiveRecord::Migration[7.1]
  # A reduced-fare monthly (senior, disabled, youth). A rider category is
  # reduced-fare when its one-trip fare is below the Adult fare, so this
  # follows the fare sheet without another flag to maintain. 0 = same price
  # as the full monthly.
  def change
    add_column :providers, :fare_monthly_pass_price_reduced, :decimal, precision: 6, scale: 2, null: false, default: 0
  end
end
