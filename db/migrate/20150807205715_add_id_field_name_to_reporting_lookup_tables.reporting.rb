# This migration comes from reporting (originally 20150414193831)
class AddIdFieldNameToReportingLookupTables < ActiveRecord::Migration[4.2]
  def change
    add_column :reporting_lookup_tables, :id_field_name, :string, null: false, default: 'id'
  end
end
