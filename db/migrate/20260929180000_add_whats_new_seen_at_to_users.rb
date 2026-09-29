class AddWhatsNewSeenAtToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :whats_new_seen_at, :datetime   # when the user last opened What's new
  end
end
