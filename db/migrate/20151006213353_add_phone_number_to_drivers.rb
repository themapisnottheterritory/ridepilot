class AddPhoneNumberToDrivers < ActiveRecord::Migration[4.2]
  def change
    add_column :drivers, :phone_number, :string
  end
end
