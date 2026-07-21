class CreateGpsLocationsView < ActiveRecord::Migration[7.1]
  def up
    execute "CREATE OR REPLACE VIEW gps_locations_view AS SELECT * FROM gps_locations"
  end

  def down
    execute "DROP VIEW IF EXISTS gps_locations_view"
  end
end
