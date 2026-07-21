class AddIsGroupToReportingOutputFields < ActiveRecord::Migration[4.2]
  def change
    add_column :reporting_output_fields, :is_group, :boolean, default: false
  end
end
