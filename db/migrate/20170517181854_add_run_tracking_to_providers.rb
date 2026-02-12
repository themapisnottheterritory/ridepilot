class AddRunTrackingToProviders < ActiveRecord::Migration[4.2]
  def change
    add_column :providers, :run_tracking, :boolean
  end
end
