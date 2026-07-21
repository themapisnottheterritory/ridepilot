class AddIsStandByToTrips < ActiveRecord::Migration[4.2]
  def change
    add_column :trips, :is_stand_by, :boolean
  end
end
