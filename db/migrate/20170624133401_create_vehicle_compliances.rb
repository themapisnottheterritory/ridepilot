class CreateVehicleCompliances < ActiveRecord::Migration[4.2]
  def change
    create_table :vehicle_compliances do |t|
      t.references :vehicle, index: true
      t.string :event
      t.text :notes
      t.date :due_date
      t.date :compliance_date
      t.references :vehicle_requirement_template, index: true
      t.boolean :legal

      t.timestamps
    end
  end
end
