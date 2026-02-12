class AddDeletedAtToLookupConfigurationTable < ActiveRecord::Migration[4.2]
  def change
    add_column :lookup_tables, :deleted_at, :datetime
    add_index :lookup_tables, :deleted_at
  end
end
