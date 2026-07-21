class AddMoreFieldsToUsers < ActiveRecord::Migration[4.2]
  def change
    add_column :users, :first_name, :string
    add_column :users, :last_name, :string
    add_column :users, :username, :string
    add_column :users, :phone_number, :string
    add_reference :users, :address, index: true
  end
end
