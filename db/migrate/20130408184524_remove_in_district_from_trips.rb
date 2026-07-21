class RemoveInDistrictFromTrips < ActiveRecord::Migration[4.2]
  def self.up
    remove_column :trips, :in_district
  end

  def self.down
    add_column :trips, :in_district
  end
end
