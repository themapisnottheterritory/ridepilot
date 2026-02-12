class AddGarageToRuns < ActiveRecord::Migration[4.2]
  def change
    add_column :runs, :from_garage_address_id, :integer
    add_column :runs, :to_garage_address_id, :integer
    add_index :runs, :from_garage_address_id
    add_index :runs, :to_garage_address_id
  end
end
