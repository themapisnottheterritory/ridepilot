class CreateBookingUsers < ActiveRecord::Migration[4.2]
  def change
    create_table :booking_users do |t|
      t.references :user, index: true
      t.string :token

      t.timestamps
    end
  end
end
