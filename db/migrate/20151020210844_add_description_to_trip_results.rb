class AddDescriptionToTripResults < ActiveRecord::Migration[4.2]
  def change
    add_column :trip_results, :description, :string
  end
end
