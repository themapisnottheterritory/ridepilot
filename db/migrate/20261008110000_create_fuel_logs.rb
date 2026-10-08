# Every time a bus takes fuel (tablet 1.0.34): the "Log fuel" button mid-shift,
# and the post-trip's Gallons Fueled at the end of the day, in one place for
# the bus page and the Vehicle Summary. Price and total come from the pump
# photo when the scan read them; drivers only type gallons.
class CreateFuelLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :fuel_logs do |t|
      t.bigint   :provider_id
      t.bigint   :vehicle_id, null: false
      t.bigint   :run_id
      t.bigint   :driver_id
      t.bigint   :vehicle_inspection_report_id   # post-trip entries
      t.string   :source, null: false             # mid_shift | post_trip
      t.decimal  :gallons, precision: 8, scale: 3, null: false
      t.decimal  :price_per_gallon, precision: 8, scale: 3
      t.decimal  :total_cost, precision: 10, scale: 2
      t.integer  :odometer
      t.datetime :fueled_at, null: false
      t.string   :client_uuid                      # the tablet's id, so a resend isn't a second fill
      t.text     :notes
      t.timestamps
    end
    add_index :fuel_logs, [:vehicle_id, :fueled_at]
    add_index :fuel_logs, :client_uuid, unique: true
    add_column :reading_scans, :fuel_log_id, :bigint
  end
end
