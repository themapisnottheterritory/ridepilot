class AddCustomerReferenceToAddresses < ActiveRecord::Migration[4.2]
  def up
    add_reference :addresses, :customer, index: true

    CustomerAddress.includes(:address).references(:address).all.each do |customer_address|
      customer_address.address.update_attribute(:customer_id, customer_address.customer_id) if customer_address.address
    end

    rename_table :addresses_customers, :addresses_customers_old
  end

  def down
    rename_table :addresses_customers_old, :addresses_customers

    Address.where.not(customer_id: nil).each do |address|
      CustomerAddress.where(address_id: address.id, customer_id: address.customer_id).first_or_create
    end

    remove_reference :addresses, :customer
  end
end
