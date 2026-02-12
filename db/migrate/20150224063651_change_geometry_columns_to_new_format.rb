class ChangeGeometryColumnsToNewFormat < ActiveRecord::Migration[4.2]
  def up
    remove_column :addresses, :the_geom
    add_column :addresses, :the_geom, :point, geographic: true, srid: 4326
    add_index :addresses, :the_geom, using: :gist

    remove_column :providers, :region_nw_corner
    remove_column :providers, :region_se_corner
    remove_column :providers, :viewport_center
    add_column :providers, :region_nw_corner, :point, geographic: true, srid: 4326
    add_column :providers, :region_se_corner, :point, geographic: true, srid: 4326
    add_column :providers, :viewport_center, :point, geographic: true, srid: 4326

    remove_column :regions, :the_geom
    add_column :regions, :the_geom, :polygon, geographic: true, srid: 4326
    add_index :regions, :the_geom, using: :gist

    Address.all.each(&:save!)
    Provider.all.each(&:save!)
    Region.all.each(&:save!)      
  end

  def down
    remove_column :addresses, :the_geom
    add_column :addresses, :the_geom, :point, srid: 4326
    add_index :addresses, :the_geom, using: :gist
    
    remove_column :providers, :region_nw_corner
    remove_column :providers, :region_se_corner
    remove_column :providers, :viewport_center
    add_column :providers, :region_nw_corner, :point, srid: 4326
    add_column :providers, :region_se_corner, :point, srid: 4326
    add_column :providers, :viewport_center, :point, srid: 4326

    remove_column :regions, :the_geom
    add_column :regions, :the_geom, :polygon, srid: 4326
    add_index :regions, :the_geom, using: :gist

    Address.all.each(&:save!)
    Provider.all.each(&:save!)
    Region.all.each(&:save!)      
  end
end
