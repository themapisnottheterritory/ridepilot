class AddIsElderlyToCustomers < ActiveRecord::Migration[4.2]
  def change
    add_column :customers, :is_elderly, :boolean, default: false
  end
end
