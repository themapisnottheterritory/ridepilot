class AddCountyToAddresses < ActiveRecord::Migration[7.1]
  # Gives the county somewhere of its own to live.
  #
  # It had been kept in address_group, which the model and the reports both
  # treat as the address TYPE -- AddressGroup::UNKNOWN_TYPE is 'Needs Update',
  # and ReportsController labels the filter "Address Type". Eight real
  # categories were set up for it (Medical, Dialysis, Senior Center and the
  # rest) and never used, because 34 counties were occupying the field.
  #
  # One field cannot be both. County moves here, address_group goes back to
  # meaning what the rest of the code already assumes it means.
  def change
    add_column :addresses, :county, :string
    add_index :addresses, :county
  end
end
