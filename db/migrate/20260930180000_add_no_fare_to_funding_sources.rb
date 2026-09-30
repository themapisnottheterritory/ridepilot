# A funding source that pays for the whole ride, so the rider pays nothing:
# Lavaca's Title III riders, billed monthly to New Horizons (Kristie,
# 2026-09-30). fare_note says who is billed; drivers and the office see it.
class AddNoFareToFundingSources < ActiveRecord::Migration[7.1]
  def change
    add_column :funding_sources, :no_fare, :boolean, default: false, null: false
    add_column :funding_sources, :fare_note, :string
  end
end
