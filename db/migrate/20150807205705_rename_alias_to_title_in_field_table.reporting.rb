# This migration comes from reporting (originally 20150328224244)
class RenameAliasToTitleInFieldTable < ActiveRecord::Migration[4.2]
  def change
    rename_column :reporting_fields, :alias, :title
  end
end
