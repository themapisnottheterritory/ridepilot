class AddRepeatingRunToRepeatingTrips < ActiveRecord::Migration[4.2]
  def change
    add_reference :repeating_trips, :repeating_run, index: true
  end
end
