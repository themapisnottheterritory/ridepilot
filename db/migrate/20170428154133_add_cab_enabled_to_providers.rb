class AddCabEnabledToProviders < ActiveRecord::Migration[4.2]
  def change
    add_column :providers, :cab_enabled, :boolean
  end
end
