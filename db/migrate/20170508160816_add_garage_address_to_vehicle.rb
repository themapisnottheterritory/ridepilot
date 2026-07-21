class AddGarageAddressToVehicle < ActiveRecord::Migration[4.2]
  def change
    add_column :vehicles, :garage_address_id, :integer
    add_index :vehicles, :garage_address_id
  end
end
