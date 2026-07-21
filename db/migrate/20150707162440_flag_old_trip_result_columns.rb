class FlagOldTripResultColumns < ActiveRecord::Migration[4.2]
  def change
    rename_column :trips, :trip_result, :trip_result_old
  end
end
