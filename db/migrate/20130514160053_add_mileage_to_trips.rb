class AddMileageToTrips < ActiveRecord::Migration[4.2]
  def self.up
    add_column :trips, :mileage, :integer
  end

  def self.down
    remove_column :trips, :mileage
  end
end
