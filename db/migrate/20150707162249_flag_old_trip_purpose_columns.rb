class FlagOldTripPurposeColumns < ActiveRecord::Migration[4.2]
  def change
    rename_column :trips, :trip_purpose, :trip_purpose_old
    rename_column :repeating_trips, :trip_purpose, :trip_purpose_old
    rename_column :addresses, :default_trip_purpose, :trip_purpose_old
  end
end
