class AddInactivatedDatesToDrivers < ActiveRecord::Migration[4.2]
  def change
    add_column :drivers, :inactivated_start_date, :date
    add_column :drivers, :inactivated_end_date, :date
    add_column :drivers, :active_status_changed_reason, :text
  end
end
