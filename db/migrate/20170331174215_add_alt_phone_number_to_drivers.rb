class AddAltPhoneNumberToDrivers < ActiveRecord::Migration[4.2]
  def change
    add_column :drivers, :alt_phone_number, :string
  end
end
