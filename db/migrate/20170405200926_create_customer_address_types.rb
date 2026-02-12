class CreateCustomerAddressTypes < ActiveRecord::Migration[4.2]
  def change
    create_table :customer_address_types do |t|
      t.string :name
      t.string :code
    end
  end
end
