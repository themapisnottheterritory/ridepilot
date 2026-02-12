class ChangeAddressAddPhoneNumber < ActiveRecord::Migration[4.2]
  def self.up
    add_column :addresses, :phone_number, :string
  end

  def self.down
    remove_column :addresses, :phone_number
  end
end
