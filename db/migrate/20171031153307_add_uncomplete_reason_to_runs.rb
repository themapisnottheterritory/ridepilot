class AddUncompleteReasonToRuns < ActiveRecord::Migration[4.2]
  def change
    add_column :runs, :uncomplete_reason, :text
  end
end
