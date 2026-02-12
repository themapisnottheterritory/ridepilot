class DeviseUpdateUserExpireFields < ActiveRecord::Migration[4.2]
 def change
  add_column :users, :expires_at, :datetime
 end
end