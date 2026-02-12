class AddDeletedAtToCustomerAddressTypes < ActiveRecord::Migration[4.2]
  def change
    add_column :customer_address_types, :deleted_at, :datetime
  end
end
