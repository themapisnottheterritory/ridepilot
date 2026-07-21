class AddCustomerNonsharableToProviders < ActiveRecord::Migration[4.2]
  def change
    add_column :providers, :customer_nonsharable, :boolean, default: false
  end
end
