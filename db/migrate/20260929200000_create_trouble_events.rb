# The trouble board's raw material (TroubleWatch): where RidePilot got in
# people's way. Deliberately no user, IP or request data -- only the screen,
# the agency and what happened.
class CreateTroubleEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :trouble_events do |t|
      t.string  :kind, null: false          # error | message | slow
      t.string  :screen                     # "Dispatch", "Trips", "Driver tablet" ...
      t.string  :action                     # controller#action, e.g. "trips#create"
      t.string  :detail                     # error class and message, or the message shown
      t.integer :provider_id
      t.integer :duration_ms
      t.datetime :created_at, null: false
    end
    add_index :trouble_events, :created_at
    add_index :trouble_events, [:kind, :created_at]
  end
end
