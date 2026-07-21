class AddAddressGroupToAddresses < ActiveRecord::Migration[4.2]
  def change
    add_reference :addresses, :address_group, index: true
  end
end
