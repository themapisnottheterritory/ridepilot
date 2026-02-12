class AddDirectionToTrips < ActiveRecord::Migration[4.2]
  def change
    add_column :trips, :direction, :string, default: :outbound
  end
end
