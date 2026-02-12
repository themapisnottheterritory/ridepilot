class AddCommentsToRepeatingTrips < ActiveRecord::Migration[4.2]
  def change
    add_column :repeating_trips, :comments, :string
  end
end
