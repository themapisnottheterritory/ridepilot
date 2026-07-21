class AddCancelledToRuns < ActiveRecord::Migration[4.2]
  def change
    add_column :runs, :cancelled, :boolean
  end
end
