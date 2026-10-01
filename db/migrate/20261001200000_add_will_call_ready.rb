# "Will call ready" (2026-10-01): dispatch presses it when a will-call rider
# phones in; the driver's tablet gets a message tied to that trip.
class AddWillCallReady < ActiveRecord::Migration[7.1]
  def change
    add_column :trips, :will_call_ready_at, :datetime
    add_column :trips, :will_call_ready_by_id, :integer
    add_column :messages, :trip_id, :integer
    add_index :messages, :trip_id
  end
end
