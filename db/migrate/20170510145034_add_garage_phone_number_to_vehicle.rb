class AddGaragePhoneNumberToVehicle < ActiveRecord::Migration[4.2]
  def change
    add_column :vehicles, :garage_phone_number, :string
  end
end
