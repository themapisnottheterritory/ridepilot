class AddEndsOnToFareScheduleRows < ActiveRecord::Migration[7.1]
  # A county table can stop applying on a date: Gonzales rides free until
  # its fares are reinstated on 2026-10-01 (FY27 Fare Structure). Compared
  # with the trip's date, so a trip booked now for October is quoted the fare.
  # NULL = no end.
  def change
    add_column :fare_schedule_rows, :ends_on, :date
  end
end
