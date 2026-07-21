class CreateDriverHistories < ActiveRecord::Migration[4.2]
  def change
    create_table :driver_histories do |t|
      t.references :driver, index: true
      t.string :event
      t.text :notes
      t.date :event_date

      t.timestamps
    end
  end
end
