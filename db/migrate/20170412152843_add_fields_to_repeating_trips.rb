class AddFieldsToRepeatingTrips < ActiveRecord::Migration[4.2]
  def change
    add_reference :repeating_trips, :service_level, index: true unless column_exists?(:repeating_trips, :service_level_id)
    add_column :repeating_trips, :medicaid_eligible, :boolean unless column_exists?(:repeating_trips, :medicaid_eligible)
    add_column :repeating_trips, :mobility_device_accommodations, :integer unless column_exists?(:repeating_trips, :mobility_device_accommodations)
  end
end
