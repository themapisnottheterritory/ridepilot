class CreateCustomerEligibilities < ActiveRecord::Migration[4.2]
  def change
    create_table :customer_eligibilities do |t|
      t.references :customer, index: true
      t.references :eligibility, index: true
      t.text :ineligible_reason

      t.timestamps
    end
  end
end
