class AddCustomerInformedToRepeatingTrips < ActiveRecord::Migration[4.2]
  def self.up
    add_column :repeating_trips, :customer_informed, :boolean
  end

  def self.down
    remove_column :repeating_trips, :customer_informed
  end
end
