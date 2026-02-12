class AddIndexToOperatingHours < ActiveRecord::Migration[4.2]
  def change
    add_index :operating_hours, [:operatable_id, :operatable_type]
  end
end
