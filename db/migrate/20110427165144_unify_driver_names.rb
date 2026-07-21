class UnifyDriverNames < ActiveRecord::Migration[4.2]
  def self.up
    add_column :drivers, :name, :string
    for driver in Driver.all
      driver.name = "%s %s" % [driver.first_name, driver.last_name]
      driver.save!
    end
    remove_column :drivers, :first_name
    remove_column :drivers, :last_name

  end

  def self.down
  end
end
