class CreateSuggestions < ActiveRecord::Migration[7.1]
  def change
    create_table :suggestions do |t|
      t.integer :user_id, null: false
      t.integer :provider_id
      t.string  :kind, null: false, default: "idea"      # idea | problem | question
      t.text    :body, null: false
      t.string  :page_path                                # the screen it's about
      t.integer :help_question_id                         # sent from an Ask RidePilot answer
      t.string  :status, null: false, default: "new"     # new | planned | done | not_planned
      t.text    :reply                                    # I.T.'s answer, shown to the sender
      t.integer :replied_by_id
      t.timestamps
    end
    add_index :suggestions, :user_id
    add_index :suggestions, :provider_id
    add_index :suggestions, :status
  end
end
