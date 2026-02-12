class AddFieldsToProviders < ActiveRecord::Migration[4.2]
  def change
    add_column :providers, :phone_number, :string
    add_column :providers, :alt_phone_number, :string
    add_column :providers, :url, :string
    add_column :providers, :primary_contact_name, :string
    add_column :providers, :primary_contact_phone_number, :string
    add_column :providers, :primary_contact_email, :string
    add_column :providers, :business_address_id, :integer
    add_column :providers, :mailing_address_id, :integer
    add_column :providers, :admin_name, :string
    add_index :providers, :business_address_id
    add_index :providers, :mailing_address_id
  end
end
