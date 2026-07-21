class RemoveSdsdPerRideReimbursementRateFromProviders < ActiveRecord::Migration[4.2]
  def self.up
    remove_column :providers, :sdsd_per_ride_reimbursement_rate
  end

  def self.down
    add_column :providers, :sdsd_per_ride_reimbursement_rate, :decimal, :precision => 8, :scale => 2
  end
end
