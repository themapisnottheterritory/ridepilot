class AddDataAccessFieldsToReportingLookupTables < ActiveRecord::Migration[4.2]
  def change
    add_column :reporting_lookup_tables, :data_access_type, :string
  end
end
