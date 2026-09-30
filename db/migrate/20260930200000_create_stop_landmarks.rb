# Next Bus: recognisable places near each fixed-route stop ("by the
# Whataburger"), so CSRs and riders can agree on where a stop is. Seeded from
# the map (source "map"); CSRs add their own and hide bad ones (source
# "staff"). stop_id is the published timetable's stop_id.
class CreateStopLandmarks < ActiveRecord::Migration[7.1]
  def change
    create_table :stop_landmarks do |t|
      t.string  :stop_id, null: false
      t.string  :name, null: false
      t.string  :kind
      t.decimal :lat, precision: 9, scale: 6
      t.decimal :lon, precision: 9, scale: 6
      t.integer :meters
      t.boolean :brand, default: false, null: false
      t.string  :source, default: "staff", null: false
      t.boolean :hidden, default: false, null: false
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :stop_landmarks, :stop_id
    add_index :stop_landmarks, "stop_id, lower(name)", unique: true, name: "index_stop_landmarks_on_stop_and_name"
  end
end
