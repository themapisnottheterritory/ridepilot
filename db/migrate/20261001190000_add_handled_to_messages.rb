# Dispatch inbox (2026-10-01): a driver's message is "handled" once any
# dispatcher opens or answers that driver's chat, so the whole desk sees it
# taken care of and two people don't both call the driver.
class AddHandledToMessages < ActiveRecord::Migration[7.1]
  def change
    add_column :messages, :handled_at, :datetime
    add_column :messages, :handled_by_id, :integer
    add_index :messages, [:provider_id, :handled_at]
  end
end
