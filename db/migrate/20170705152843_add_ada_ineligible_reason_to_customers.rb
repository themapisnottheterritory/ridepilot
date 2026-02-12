class AddAdaIneligibleReasonToCustomers < ActiveRecord::Migration[4.2]
  def change
    add_column :customers, :ada_ineligible_reason, :text
  end
end
