class AddScheduledThroughToRepeatingRuns < ActiveRecord::Migration[4.2]
  def change
    add_column :repeating_runs, :scheduled_through, :date
  end
end
