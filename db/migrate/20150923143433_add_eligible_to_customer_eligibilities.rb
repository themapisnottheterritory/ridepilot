class AddEligibleToCustomerEligibilities < ActiveRecord::Migration[4.2]
  def change
    add_column :customer_eligibilities, :eligible, :boolean
  end
end
