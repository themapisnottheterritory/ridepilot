class AddTypeToAddresses < ActiveRecord::Migration[4.2]
  def change
    add_column :addresses, :type, :string
  end
end
