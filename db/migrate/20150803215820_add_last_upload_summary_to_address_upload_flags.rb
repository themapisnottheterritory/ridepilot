class AddLastUploadSummaryToAddressUploadFlags < ActiveRecord::Migration[4.2]
  def change
    add_column :address_upload_flags, :last_upload_summary, :text
  end
end
