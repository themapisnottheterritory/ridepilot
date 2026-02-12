class AddDeletedAtToEmergencyContact < ActiveRecord::Migration[4.2]
  def change
    add_column :emergency_contacts, :deleted_at, :datetime
  end
end
