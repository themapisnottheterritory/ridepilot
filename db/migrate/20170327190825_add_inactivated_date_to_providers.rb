class AddInactivatedDateToProviders < ActiveRecord::Migration[4.2]
  def change
    add_column :providers, :inactivated_date, :datetime
    add_column :providers, :inactivated_reason, :string
  end
end
