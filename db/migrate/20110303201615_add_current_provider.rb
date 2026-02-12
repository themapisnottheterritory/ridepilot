class AddCurrentProvider < ActiveRecord::Migration[4.2]
  def self.up
    add_column :users, :current_provider_id, :integer
  end

  def self.down
    remove_column :users, :current_provider_id
  end
end
