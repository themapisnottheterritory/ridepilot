class AddDriverAvailabilitySettingsToProviders < ActiveRecord::Migration[4.2]
  def change
    add_column :providers, :driver_availability_min_hour, :integer, default: 6
    add_column :providers, :driver_availability_max_hour, :integer, default: 22
    add_column :providers, :driver_availability_interval_min, :integer, default: 30
    add_column :providers, :driver_availability_days_ahead, :integer, default: 30
  end
end
