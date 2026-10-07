# Every stop a driver's tablet has been shown on today's run, so a stop that
# later leaves the manifest (cancelled, no-show drop-off, moved to another run)
# can stay on the tablet crossed out with the reason instead of vanishing
# (UDR drivers, 2026-10-07: "I could have sworn I saw Mary Ramos on here").
class CreateManifestSeenStops < ActiveRecord::Migration[7.1]
  def change
    create_table :manifest_seen_stops do |t|
      t.integer :run_id, null: false
      t.integer :trip_id, null: false
      t.integer :leg_flag, null: false
      t.integer :itinerary_id
      t.string :customer_name
      t.string :address_text
      t.datetime :time
      t.datetime :created_at, null: false
    end
    add_index :manifest_seen_stops, [:run_id, :trip_id, :leg_flag], unique: true, name: "index_manifest_seen_stops_on_run_trip_leg"
  end
end
