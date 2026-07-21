class AddCodeToCustomers < ActiveRecord::Migration[4.2]
  def change
    add_column :customers, :code, :string
  end
end
