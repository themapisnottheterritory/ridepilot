class AddPassProducts < ActiveRecord::Migration[7.1]
  # Pass products (docs/fare-card-design.md, section 16). A 10- or 20-trip
  # pass is stored value: the card is credited trips x the rider's category
  # fare, while the office may take less cash if a discount is set. tendered
  # is what was actually paid when it differs from the value credited; the
  # activity report sums cash and checks from it. A monthly pass is a load of
  # the pass price followed by a "pass" debit of the same amount, so the
  # money is on the ledger and the balance is unchanged, and the customer's
  # fare_pass_expires_on is moved to the end of the month sold.
  def change
    add_column :fare_transactions, :tendered, :decimal, precision: 8, scale: 2
    add_column :providers, :fare_monthly_pass_price, :decimal, precision: 6, scale: 2, null: false, default: 0
    add_column :providers, :fare_multi_trip_discount_pct, :integer, null: false, default: 0
  end
end
