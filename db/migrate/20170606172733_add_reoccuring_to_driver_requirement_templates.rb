class AddReoccuringToDriverRequirementTemplates < ActiveRecord::Migration[4.2]
  def change
    add_column :driver_requirement_templates, :reoccuring, :boolean
  end
end
