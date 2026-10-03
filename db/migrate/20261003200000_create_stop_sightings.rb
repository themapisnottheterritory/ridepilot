# Where drivers stop (Philz 2026-10-03): where the van actually sat still while a
# driver did a pickup or drop-off, from the bus GPS (Pepwave AVL on .40), one row per
# finished stop. Several visits that agree become the place drivers stop for that
# address; a pin far from it goes on Pins to check, and staff decide (pin_checks).
class CreateStopSightings < ActiveRecord::Migration[7.1]
  def change
    create_table :stop_sightings do |t|
      t.integer  :address_id, null: false
      t.integer  :itinerary_id, null: false
      t.integer  :run_id
      t.integer  :vehicle_id
      t.integer  :provider_id
      t.datetime :seen_at, null: false        # when the van left (end of the stop)
      t.integer  :dwell_secs
      t.float    :latitude, null: false
      t.float    :longitude, null: false
      t.string   :source, null: false, default: "avl"
      t.timestamps
    end
    add_index :stop_sightings, :itinerary_id, unique: true
    add_index :stop_sightings, :address_id

    create_table :pin_checks do |t|
      t.integer :address_id, null: false
      t.string  :decision, null: false        # moved / kept
      t.float   :from_latitude
      t.float   :from_longitude
      t.float   :to_latitude
      t.float   :to_longitude
      t.integer :visits
      t.integer :user_id
      t.timestamps
    end
    add_index :pin_checks, :address_id
  end
end
