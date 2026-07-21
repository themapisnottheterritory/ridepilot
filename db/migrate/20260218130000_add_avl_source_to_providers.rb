class AddAvlSourceToProviders < ActiveRecord::Migration[7.1]
  def change
    add_column :providers, :avl_source, :string, default: 'opentransit_api'
    add_column :providers, :busavl_host, :string
    add_column :providers, :busavl_database, :string
    add_column :providers, :busavl_username, :string
    add_column :providers, :busavl_password, :string
  end
end
