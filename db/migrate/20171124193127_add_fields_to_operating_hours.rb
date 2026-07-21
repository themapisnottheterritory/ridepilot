class AddFieldsToOperatingHours < ActiveRecord::Migration[4.2]
  def change
    add_column :operating_hours, :is_all_day, :boolean, default: false
    add_column :operating_hours, :is_unavailable, :boolean, default: false
    add_column :daily_operating_hours, :is_all_day, :boolean, default: false
    add_column :daily_operating_hours, :is_unavailable, :boolean, default: false
  end
end
