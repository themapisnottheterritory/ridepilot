class AddDateRangeToRepeatingTrips < ActiveRecord::Migration[4.2]
  def change
    add_column :repeating_trips, :start_date, :date
    add_column :repeating_trips, :end_date, :date
  end
end
