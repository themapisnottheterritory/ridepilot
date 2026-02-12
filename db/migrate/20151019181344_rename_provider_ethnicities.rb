class RenameProviderEthnicities < ActiveRecord::Migration[4.2]
  def change
    remove_index :provider_ethnicities, :provider_id if index_exists?(:provider_ethnicities, :provider_id)
    remove_column :provider_ethnicities, :provider_id, :integer
    rename_table :provider_ethnicities, :ethnicities
  end
end
