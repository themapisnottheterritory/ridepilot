class AddCountyFares < ActiveRecord::Migration[7.1]
  # Each county GCRPC serves publishes its own rural fare (gcrpc.org, Golden
  # Crescent Transit Rural -> Fare Schedule), so one distance table per
  # provider was not enough.
  #
  # fare_schedule_rows.county: the county whose riders the table prices. ''
  # is the provider's default table, used for any county without its own.
  # Not NULL so the cell index stays unique on Postgres 9.4.
  #
  # fare_zone_rows: counties that price by where the trip goes instead of how
  # far (Jackson, Matagorda): within a town, within the county, to another
  # county GCRPC serves, or to a named city.
  def change
    add_column :fare_schedule_rows, :county, :string, null: false, default: ""
    remove_index :fare_schedule_rows, name: "idx_fare_schedule_rows_cell"
    add_index :fare_schedule_rows, [:provider_id, :service, :county, :up_to_miles, :rider_category_id],
              unique: true, name: "idx_fare_schedule_rows_cell"

    create_table :fare_zone_rows do |t|
      t.integer :provider_id, null: false
      t.string  :county, null: false
      t.string  :zone, null: false          # town | county | other_county | city
      t.string  :place                      # the town or city name for town and city zones
      t.integer :rider_category_id, null: false
      t.decimal :fare, precision: 7, scale: 2, null: false, default: 0
      t.timestamps
    end
    add_index :fare_zone_rows, [:provider_id, :county, :zone, :place, :rider_category_id],
              unique: true, name: "idx_fare_zone_rows_cell"
  end
end
