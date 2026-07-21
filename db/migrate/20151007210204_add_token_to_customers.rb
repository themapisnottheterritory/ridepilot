class AddTokenToCustomers < ActiveRecord::Migration[4.2]
  def change
    add_column :customers, :token, :string
  end
end
