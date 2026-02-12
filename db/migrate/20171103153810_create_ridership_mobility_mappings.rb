class CreateRidershipMobilityMappings < ActiveRecord::Migration[4.2]
  def change
    create_table :ridership_mobility_mappings do |t|
      t.integer :ridership_id
      t.references :mobility, index: true
      t.integer :capacity
      t.string :type
      t.integer :host_id

      t.timestamps
    end
  end
end
