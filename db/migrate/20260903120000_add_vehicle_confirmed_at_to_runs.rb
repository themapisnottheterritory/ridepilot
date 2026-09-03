class AddVehicleConfirmedAtToRuns < ActiveRecord::Migration[7.1]
  # Stamped by the driver tablet at run start, when the driver either confirms
  # the assigned unit or picks the one they are actually driving. Nil means no
  # driver has confirmed the vehicle on this run yet.
  def change
    add_column :runs, :vehicle_confirmed_at, :datetime
  end
end
