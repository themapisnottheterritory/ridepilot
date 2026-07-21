class CreateDonations < ActiveRecord::Migration[4.2]
  def change
    create_table :donations do |t|
      t.datetime :date
      t.float :amount
      t.text :notes
      t.datetime :deleted_at

      t.timestamps
    end
  end
end
