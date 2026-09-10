class AddParatransitFareToProviders < ActiveRecord::Migration[7.1]
  # Urban demand response (ADA paratransit) is a flat fare, $1.50 on the
  # 2026-09-01 fare sheet, for an ADA-eligible rider whose trip stays inside
  # the urban service area. The area is a list of city names on the trip's
  # addresses; there is no urban polygon in the system (regions is empty and
  # in_district means the eight-county area).
  def change
    add_column :providers, :fare_paratransit, :decimal, precision: 6, scale: 2, null: false, default: 0
    add_column :providers, :fare_urban_cities, :string, null: false, default: "Victoria"
  end
end
