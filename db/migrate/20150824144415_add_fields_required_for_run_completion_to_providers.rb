class AddFieldsRequiredForRunCompletionToProviders < ActiveRecord::Migration[4.2]
  def change
    add_column :providers, :fields_required_for_run_completion, :text
  end
end
