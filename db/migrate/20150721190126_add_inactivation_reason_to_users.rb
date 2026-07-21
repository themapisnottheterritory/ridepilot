class AddInactivationReasonToUsers < ActiveRecord::Migration[4.2]
  def change
    add_column :users, :inactivation_reason, :string
  end
end
