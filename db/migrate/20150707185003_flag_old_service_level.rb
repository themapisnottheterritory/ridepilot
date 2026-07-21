class FlagOldServiceLevel < ActiveRecord::Migration[4.2]
  def change
    rename_column :trips, :service_level, :service_level_old
    rename_column :customers, :default_service_level, :service_level_old
  end
end
