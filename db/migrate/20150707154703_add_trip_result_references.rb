class AddTripResultReferences < ActiveRecord::Migration[4.2]
  def change
    add_reference :trips, :trip_result, index: true
  end
end
