class CreatePlannedLeaves < ActiveRecord::Migration[4.2]
  def change
    create_table :planned_leaves do |t|
      t.date :start_date
      t.date :end_date
      t.text :reason
      t.integer :leavable_id
      t.string :leavable_type

      t.timestamps
    end

    add_index :planned_leaves, [:leavable_id, :leavable_type]
  end
end
