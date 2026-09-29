class CreateHelpQuestions < ActiveRecord::Migration[7.1]
  # Ask RidePilot: every question staff ask the help panel and what it answered,
  # so operations can see where people get stuck and fix the guide or the screen.
  def change
    create_table :help_questions do |t|
      t.integer :user_id
      t.integer :provider_id
      t.string  :page_path
      t.string  :page_title
      t.text    :question, null: false
      t.text    :answer
      t.string  :model
      t.integer :duration_ms
      t.boolean :helpful             # the user's thumbs up / down, nil if none
      t.string  :error
      t.timestamps
    end
    add_index :help_questions, :created_at
    add_index :help_questions, :provider_id
  end
end
