# This migration comes from reporting (originally 20150407185713)
class AddSortOrderToReportingFilterFields < ActiveRecord::Migration[4.2]
  def change
    add_column :reporting_filter_fields, :sort_order, :integer, null: false, default: 1
  end
end
