class CreateProviderLookupTables < ActiveRecord::Migration[4.2]
  def change
    create_table :provider_lookup_tables do |t|
      t.string :caption
      t.string :name
      t.string :value_column_name
      t.string :model_name
      t.string :code_column_name
      t.string :description_column_name

      t.timestamps
    end
  end
end
