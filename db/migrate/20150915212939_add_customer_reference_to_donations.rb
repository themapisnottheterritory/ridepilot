class AddCustomerReferenceToDonations < ActiveRecord::Migration[4.2]
  def change
    add_reference :donations, :customer, index: true
  end
end
