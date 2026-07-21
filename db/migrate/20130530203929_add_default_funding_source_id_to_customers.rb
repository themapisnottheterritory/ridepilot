class AddDefaultFundingSourceIdToCustomers < ActiveRecord::Migration[4.2]
  def self.up
    add_column :customers, :default_funding_source_id, :integer
  end

  def self.down
    remove_column :customers, :default_funding_source_id
  end
end
