class AddResultReasonToTrips < ActiveRecord::Migration[4.2]
  def change
    add_column :trips, :result_reason, :text
  end
end
