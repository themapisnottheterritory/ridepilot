class AddPrimeNumberToCustomers < ActiveRecord::Migration[4.2]
  def self.up
    add_column :customers, :prime_number, :string
  end

  def self.down
    remove_column :customers, :prime_number
  end
end
