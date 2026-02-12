class CreateTripPurposes < ActiveRecord::Migration[4.2]
  def change
    create_table :trip_purposes do |t|
      t.string :name

      t.timestamps
    end
  end
end
