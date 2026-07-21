class CreateVehicleRequirementTemplates < ActiveRecord::Migration[4.2]
  def change
    create_table :vehicle_requirement_templates do |t|
      t.references :provider, index: true
      t.string :name
      t.boolean :legal
      t.boolean :reoccuring
      t.datetime :deleted_at

      t.timestamps
    end
  end
end
