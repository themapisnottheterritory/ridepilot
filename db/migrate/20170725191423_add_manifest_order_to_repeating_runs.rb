class AddManifestOrderToRepeatingRuns < ActiveRecord::Migration[4.2]
  def change
    add_column :repeating_runs, :manifest_order, :text
  end
end
