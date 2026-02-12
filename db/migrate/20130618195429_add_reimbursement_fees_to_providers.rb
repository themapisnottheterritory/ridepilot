class AddReimbursementFeesToProviders < ActiveRecord::Migration[4.2]
  def self.up
    add_column :providers, :oaa3b_per_ride_reimbursement_rate,               :decimal, :precision => 8, :scale => 2
    add_column :providers, :ride_connection_per_ride_reimbursement_rate,     :decimal, :precision => 8, :scale => 2
    add_column :providers, :trimet_per_ride_reimbursement_rate,              :decimal, :precision => 8, :scale => 2
    add_column :providers, :sdsd_per_ride_reimbursement_rate,                :decimal, :precision => 8, :scale => 2
    add_column :providers, :stf_van_per_ride_reimbursement_rate,             :decimal, :precision => 8, :scale => 2
    add_column :providers, :stf_taxi_per_ride_administrative_fee,            :decimal, :precision => 8, :scale => 2
    add_column :providers, :stf_taxi_per_ride_ambulatory_load_fee,           :decimal, :precision => 8, :scale => 2
    add_column :providers, :stf_taxi_per_ride_wheelchair_load_fee,           :decimal, :precision => 8, :scale => 2
    add_column :providers, :stf_taxi_per_mile_ambulatory_reimbursement_rate, :decimal, :precision => 8, :scale => 2
    add_column :providers, :stf_taxi_per_mile_wheelchair_reimbursement_rate, :decimal, :precision => 8, :scale => 2
  end

  def self.down
    remove_column :providers, :stf_taxi_per_mile_wheelchair_reimbursement_rate
    remove_column :providers, :stf_taxi_per_mile_ambulatory_reimbursement_rate
    remove_column :providers, :stf_taxi_per_ride_wheelchair_load_fee
    remove_column :providers, :stf_taxi_per_ride_ambulatory_load_fee
    remove_column :providers, :stf_taxi_per_ride_administrative_fee
    remove_column :providers, :stf_van_per_ride_reimbursement_rate
    remove_column :providers, :sdsd_per_ride_reimbursement_rate
    remove_column :providers, :trimet_per_ride_reimbursement_rate
    remove_column :providers, :ride_connection_per_ride_reimbursement_rate
    remove_column :providers, :oaa3b_per_ride_reimbursement_rate
  end
end
