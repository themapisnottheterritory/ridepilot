class CreateCustomerAuths < ActiveRecord::Migration[7.0]
  def change
    create_table :customer_auths do |t|
      t.references :customer, null: false, foreign_key: true
      t.string :token, null: false, index: { unique: true }
      t.datetime :expires_at, null: false
      t.timestamps
    end
  end
end
