class AddScheduledThroughToRepeatingTrips < ActiveRecord::Migration[4.2]
  def change
    add_column :repeating_trips, :scheduled_through, :date
  end
end
