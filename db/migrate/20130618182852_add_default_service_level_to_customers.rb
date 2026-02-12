class AddDefaultServiceLevelToCustomers < ActiveRecord::Migration[4.2]
  def self.up
    add_column :customers, :default_service_level, :string
  end

  def self.down
    remove_column :customers, :default_service_level
  end
end
