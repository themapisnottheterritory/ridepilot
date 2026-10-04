# Every stop tap from the driver tablet (Philz 2026-10-04): when the driver made it
# (the app's own clock, 1.0.30+) and when RidePilot got it, plus where the tablet
# was (1.0.31+). A tap that arrives late was made with no signal and saved on the
# tablet; one that arrives at once was made online. Tap check only reports taps it
# can prove were made online, so a dead zone or a re-sync never looks like a
# driver catching up (TapCheck). The position also counts for vans with no bus GPS.
class CreateStopTaps < ActiveRecord::Migration[7.1]
  def change
    create_table :stop_taps do |t|
      t.integer  :itinerary_id, null: false
      t.string   :action, null: false          # depart / arrive / pickup / dropoff / noshow
      t.datetime :tapped_at                    # from the app (1.0.30+); nil from older apps
      t.datetime :received_at, null: false
      t.float    :latitude                     # 1.0.31+
      t.float    :longitude
      t.integer  :accuracy_m
      t.string   :app_version
      t.timestamps
    end
    add_index :stop_taps, [:itinerary_id, :action]
  end
end
