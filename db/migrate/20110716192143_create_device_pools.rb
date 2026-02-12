class CreateDevicePools < ActiveRecord::Migration[4.2]
  def self.up
    create_table :device_pools do |t|
      t.integer :provider_id
      t.string :name, :color
      t.timestamps
    end
  end

  def self.down
    drop_table :device_pools
  end
end
