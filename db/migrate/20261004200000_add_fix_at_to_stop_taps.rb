# When the tablet's GPS fix sent with a stop tap was taken (1.0.31). A tablet
# sitting still gets no new fixes, so a van parked at a stop sends the fix from
# when it pulled up; each use decides how old is too old (TapCheck, DriverStops).
class AddFixAtToStopTaps < ActiveRecord::Migration[7.1]
  def change
    add_column :stop_taps, :fix_at, :datetime
  end
end
