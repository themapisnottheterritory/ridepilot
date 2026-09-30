# Ask RidePilot "it fills, they save": the card a question produced (JSON),
# and what happened when its button was clicked.
class AddActionToHelpQuestions < ActiveRecord::Migration[7.1]
  def change
    add_column :help_questions, :action, :text
    add_column :help_questions, :acted_at, :datetime
    add_column :help_questions, :action_result, :string
  end
end
