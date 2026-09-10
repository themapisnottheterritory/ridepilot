class CreateFareScheduleRows < ActiveRecord::Migration[7.1]
  # Distance-band fares (docs/fare-card-design.md, section 15). The published
  # rural and commuter schedules price a trip by mileage band x rider
  # category; a row here is one cell of that table. up_to_miles is the band's
  # upper edge (5, 10, 15, 20) and NULL means "anything beyond"; the band a
  # trip falls in is the first row, in up_to_miles order, that the trip's
  # drive_distance does not exceed. service names the schedule the row
  # belongs to: demand_response today, commuter later.
  def change
    create_table :fare_schedule_rows do |t|
      t.integer :provider_id, null: false
      t.string  :service, null: false, default: "demand_response"
      t.decimal :up_to_miles, precision: 6, scale: 1
      t.integer :rider_category_id, null: false
      t.decimal :fare, precision: 6, scale: 2, null: false, default: 0
      t.timestamps
    end
    add_index :fare_schedule_rows, [:provider_id, :service, :up_to_miles, :rider_category_id],
              unique: true, name: "idx_fare_schedule_rows_cell"
  end
end
