class RemoveIsProviderSpecificFromLookupTables < ActiveRecord::Migration[4.2]
  def change
    remove_column :lookup_tables, :is_provider_specific, :boolean
  end
end
