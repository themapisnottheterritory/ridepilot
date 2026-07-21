class CreateFundingAuthorizationNumbers < ActiveRecord::Migration[4.2]
  def change
    create_table :funding_authorization_numbers do |t|
      t.references :funding_source, index: true
      t.references :customer, index: true
      t.string :number
      t.text :contact_info

      t.timestamps
    end
  end
end
