# "Will call": the rider calls when ready (usually the ride home), so the
# pickup time is an estimate. Shown in the office lists and to the driver.
class AddWillCallToTrips < ActiveRecord::Migration[7.1]
  def change
    add_column :trips, :will_call, :boolean, default: false, null: false
    add_column :repeating_trips, :will_call, :boolean, default: false, null: false
  end
end
