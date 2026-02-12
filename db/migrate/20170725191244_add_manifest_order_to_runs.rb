class AddManifestOrderToRuns < ActiveRecord::Migration[4.2]
  def change
    add_column :runs, :manifest_order, :text
  end
end
