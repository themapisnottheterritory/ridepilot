class CreateTravelTrainings < ActiveRecord::Migration[4.2]
  def change
    create_table :travel_trainings do |t|
      t.belongs_to :customer, index: true
      t.datetime :date, index: true
      t.text :comment
      
      t.timestamps
    end
  end
end
