class AddAvlFieldsToProviders < ActiveRecord::Migration[7.1]
  def change
    add_column :providers, :use_external_avl, :boolean, default: false
    add_column :providers, :opentransit_url, :string
  end
end
