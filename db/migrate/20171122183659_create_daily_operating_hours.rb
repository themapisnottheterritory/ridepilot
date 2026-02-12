class CreateDailyOperatingHours < ActiveRecord::Migration[4.2]
  def change
    create_table :daily_operating_hours do |t|
      t.date :date
      t.time :start_time
      t.time :end_time
      t.integer :operatable_id
      t.string :operatable_type

      t.timestamps
    end
  end
end
