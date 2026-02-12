class AddLatLonToAddresses < ActiveRecord::Migration[4.2]
  def self.up
    add_column :addresses, :the_geom, :point, :srid => 4326
    add_index :addresses, :the_geom, using: :gist
  end

  def self.down
    remove_colum :addressses, :the_geom
  end
end
