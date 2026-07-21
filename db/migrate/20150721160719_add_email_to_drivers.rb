class AddEmailToDrivers < ActiveRecord::Migration[4.2]
  def change
    add_column :drivers, :email, :string
  end
end
