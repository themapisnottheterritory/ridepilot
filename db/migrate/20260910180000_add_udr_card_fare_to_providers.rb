class AddUdrCardFareToProviders < ActiveRecord::Migration[7.1]
  # Fare cards, phase 3 (docs/fare-card-design.md, section 5.2). A demand
  # response trip has no rider category schedule; the card fare for a trip is
  # the amount already on the trip, else this provider default.
  def change
    add_column :providers, :fare_udr_default, :decimal, precision: 6, scale: 2, null: false, default: 0
  end
end
