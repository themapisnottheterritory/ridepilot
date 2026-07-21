class ChangeDevicePoolDriversAddPostedAt < ActiveRecord::Migration[4.2]
  def self.up
    add_column :device_pool_drivers, :posted_at, :datetime
  end

  def self.down
    remove_column :device_pool_drivers, :posted_at
  end
end
