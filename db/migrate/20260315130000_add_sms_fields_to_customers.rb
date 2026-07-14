class AddSmsFieldsToCustomers < ActiveRecord::Migration[7.0]
  def change
    add_column :customers, :sms_notifications_enabled, :boolean, default: true
    add_column :customers, :preferred_language, :string, default: "en"
  end
end
