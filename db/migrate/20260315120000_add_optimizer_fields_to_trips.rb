class AddOptimizerFieldsToTrips < ActiveRecord::Migration[7.0]
  def change
    add_column :trips, :estimated_pickup_time, :datetime
  end
end
