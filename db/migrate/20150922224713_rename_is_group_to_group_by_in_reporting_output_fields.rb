class RenameIsGroupToGroupByInReportingOutputFields < ActiveRecord::Migration[4.2]
  def change
    rename_column :reporting_output_fields, :is_group, :group_by
  end
end
