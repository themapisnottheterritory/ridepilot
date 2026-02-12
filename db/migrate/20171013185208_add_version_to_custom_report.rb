class AddVersionToCustomReport < ActiveRecord::Migration[4.2]
  def change
    add_column :custom_reports, :version, :string
  end
end
