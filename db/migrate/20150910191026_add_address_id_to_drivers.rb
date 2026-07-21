class AddAddressIdToDrivers < ActiveRecord::Migration[4.2]
  def change
    add_reference :drivers, :address, index: true
  end
end
