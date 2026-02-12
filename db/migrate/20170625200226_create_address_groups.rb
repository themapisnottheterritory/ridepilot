class CreateAddressGroups < ActiveRecord::Migration[4.2]
  def change
    create_table :address_groups do |t|
      t.string :name

      t.timestamps
    end
  end
end
