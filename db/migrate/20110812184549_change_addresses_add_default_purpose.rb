class ChangeAddressesAddDefaultPurpose < ActiveRecord::Migration[4.2]
  def self.up
    add_column :addresses, :default_trip_purpose, :string
  end

  def self.down
    remove_column :addresses, :default_trip_purposes
  end
end
