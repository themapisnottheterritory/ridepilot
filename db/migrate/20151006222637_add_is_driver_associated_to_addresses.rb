class AddIsDriverAssociatedToAddresses < ActiveRecord::Migration[4.2]
  def change
    add_column :addresses, :is_driver_associated, :boolean, default: false
  end
end
