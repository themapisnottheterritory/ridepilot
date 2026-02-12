class AddIsUserAssociatedToAddresses < ActiveRecord::Migration[4.2]
  def change
    add_column :addresses, :is_user_associated, :boolean
  end
end
