class AddDeletedAtToBookingUsers < ActiveRecord::Migration[4.2]
  def change
    add_column :booking_users, :deleted_at, :datetime
  end
end
