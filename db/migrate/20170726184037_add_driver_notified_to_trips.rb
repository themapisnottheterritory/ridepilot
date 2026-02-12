class AddDriverNotifiedToTrips < ActiveRecord::Migration[4.2]
  def change
    add_column :trips, :driver_notified, :boolean
  end
end
