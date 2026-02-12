class AddIsPrimaryToRegions < ActiveRecord::Migration[4.2]
  def change
    add_column :regions, :is_primary, :boolean
  end
end
