class SetInDistrictAsFalseInAddresses < ActiveRecord::Migration[4.2]
  def change
    change_column :addresses, :in_district, :boolean, default: false
  end
end
