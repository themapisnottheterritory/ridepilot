class AddDateRangeToRepeatingRuns < ActiveRecord::Migration[4.2]
  def change
    add_column :repeating_runs, :start_date, :date
    add_column :repeating_runs, :end_date, :date
  end
end
