# Dispatch by area (Kristie, 2026-10-02): every GCRPC trip is tagged with the area the
# rider lives in -- UDR inside Victoria city limits, RVIC the rest of Victoria County,
# RCAL, JACK, RGON, DeWitt, MATA by county -- worked out from the home's map pin
# against the Census boundaries (db/data/service_areas, loaded by rake service_areas:load).
class AddServiceAreas < ActiveRecord::Migration[5.2]
  def change
    create_table :service_area_boundaries do |t|
      t.string :kind, null: false        # county / city
      t.string :name, null: false        # "Victoria", "Calhoun", ...
      t.string :geoid
      t.multi_polygon :geom, srid: 4326, null: false
      t.timestamps
    end
    add_index :service_area_boundaries, :geom, using: :gist
    add_index :service_area_boundaries, [:kind, :name], unique: true

    add_column :trips, :service_area, :string        # UDR, RVIC, RCAL, JACK, RGON, DeWitt, MATA, OUT, NOPIN
    add_column :trips, :service_area_note, :string   # "Bloomington (RVIC1)", "Yorktown (DeWitt1)"
    add_index :trips, :service_area
    add_column :customers, :service_area_override, :string   # set on the rider for homes on the city line
  end
end
