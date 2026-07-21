class ChangeTokenColumnTypeToUuid < ActiveRecord::Migration[4.2]
  def change
    remove_column :booking_users, :token, :string
    add_column :booking_users, :token, :uuid, default: 'uuid_generate_v4()'
    remove_column :customers, :token, :string
    add_column :customers, :token, :uuid, default: 'uuid_generate_v4()'
  end
end
