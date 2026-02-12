class ChangeProvidersAddScheduling < ActiveRecord::Migration[4.2]
  def self.up
    add_column :providers, :scheduling, :boolean
    Provider.all.each { |p| p.update_attribute :scheduling, true }
  end

  def self.down
    remove_column :providers, :scheduling
  end
end
