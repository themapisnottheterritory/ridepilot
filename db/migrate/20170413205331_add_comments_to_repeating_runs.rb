class AddCommentsToRepeatingRuns < ActiveRecord::Migration[4.2]
  def change
    add_column :repeating_runs, :comments, :string
  end
end
