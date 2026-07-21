class RenameClientsToCustomers < ActiveRecord::Migration[4.2]
  def self.up
    rename_table :clients, :customers
    rename_column :trips, :client_id, :customer_id
  end

  def self.down
    rename_table :customers, :clients
    rename_column :trips, :customer_id, :client_id
  end
end
