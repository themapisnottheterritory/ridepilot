class ChangeProvidersAddDispatch < ActiveRecord::Migration[4.2]
  def self.up
    add_column :providers, :dispatch, :boolean
  end

  def self.down
    remove_column :providers, :dispatch
  end
end
