class AddFareAmountsToFixedRouteLookups < ActiveRecord::Migration[7.1]
  # Victoria Transit prices a one-trip fare by rider category (Adult $1.00,
  # Senior 60+ $0.50, Disabled $0.50, Youth 5-17 $0.75, Youth 0-5 free), and
  # the fare type says whether that fare is collected at all (Cash 1.0, a
  # pass or a transfer 0). The tablet fills in fare_amount = riders x
  # default_fare x fare_factor so drivers never type an amount.
  def change
    add_column :rider_categories, :default_fare, :decimal, precision: 6, scale: 2, null: false, default: 0
    add_column :fare_types, :fare_factor, :decimal, precision: 4, scale: 2, null: false, default: 1.0
  end
end
