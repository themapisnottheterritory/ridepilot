class AddMessageToCustomers < ActiveRecord::Migration[4.2]
  def change
    add_column :customers, :message, :text
  end
end
