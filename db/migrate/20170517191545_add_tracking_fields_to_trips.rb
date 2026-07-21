class AddTrackingFieldsToTrips < ActiveRecord::Migration[4.2]
  def change
    add_column :trips, :number_of_senior_passengers_served, :integer
    add_column :trips, :number_of_disabled_passengers_served, :integer
    add_column :trips, :number_of_low_income_passengers_served, :integer
  end
end
