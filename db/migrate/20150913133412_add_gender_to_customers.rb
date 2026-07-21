class AddGenderToCustomers < ActiveRecord::Migration[4.2]
  def change
    add_column :customers, :gender, :string
  end
end
