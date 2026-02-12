class AddAliasNameToReportingOutputFields < ActiveRecord::Migration[4.2]
  def change
    add_column :reporting_output_fields, :alias_name, :string
  end
end
