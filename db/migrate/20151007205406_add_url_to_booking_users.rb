class AddUrlToBookingUsers < ActiveRecord::Migration[4.2]
  def change
    add_column :booking_users, :url, :string
  end
end
