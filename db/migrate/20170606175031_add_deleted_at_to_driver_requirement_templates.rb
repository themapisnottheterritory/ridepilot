class AddDeletedAtToDriverRequirementTemplates < ActiveRecord::Migration[4.2]
  def change
    add_column :driver_requirement_templates, :deleted_at, :datetime
  end
end
