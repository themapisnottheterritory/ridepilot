# Odometer and fuel-pump photos read by the scan model (tablet 1.0.34). Each
# scan keeps the photo, what the model read and, once the driver submits, the
# value they kept, so we can see how often a scan had to be corrected.
class CreateReadingScans < ActiveRecord::Migration[7.1]
  def change
    create_table :reading_scans do |t|
      t.string  :kind, null: false                 # odometer | pump
      t.bigint  :run_id
      t.bigint  :vehicle_id
      t.bigint  :driver_id
      t.bigint  :provider_id
      t.bigint  :vehicle_inspection_report_id
      t.jsonb   :reading, null: false, default: {}  # what the model read
      t.decimal :value, precision: 10, scale: 2     # miles or gallons
      t.decimal :accepted_value, precision: 10, scale: 2   # what the driver submitted
      t.integer :ms
      t.string  :error
      t.timestamps
    end
    add_index :reading_scans, :run_id
    add_index :reading_scans, :vehicle_inspection_report_id
  end
end
