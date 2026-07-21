class AddSortOrderToReportingOutputFields < ActiveRecord::Migration[4.2]
  def change
    add_column :reporting_output_fields, :sort_order, :integer
  end
end
