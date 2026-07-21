class AddMedicaidEligibleToTrips < ActiveRecord::Migration[4.2]
  def self.up
    add_column :trips, :medicaid_eligible, :boolean
  end

  def self.down
    remove_column :trips, :medicaid_eligible
  end
end
