class AddHomePositionToProvider < ActiveRecord::Migration[4.2]
  def self.up
    add_column :providers, :region_nw_corner, :point
    add_column :providers, :region_se_corner, :point
  end

  def self.down
    remove_column :providers, :region_nw_corner
    remove_column :providers, :region_se_corner
  end
end
