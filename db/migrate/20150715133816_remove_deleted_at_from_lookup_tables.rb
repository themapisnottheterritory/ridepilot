class RemoveDeletedAtFromLookupTables < ActiveRecord::Migration[4.2]
  def change
    remove_column :lookup_tables, :deleted_at
  end
end
