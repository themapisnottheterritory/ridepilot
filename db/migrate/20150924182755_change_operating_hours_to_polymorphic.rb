class ChangeOperatingHoursToPolymorphic < ActiveRecord::Migration[4.2]
  def change
    rename_column :operating_hours, :driver_id, :operatable_id
  end
end
