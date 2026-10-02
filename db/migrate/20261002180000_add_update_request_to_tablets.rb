# Tablets page "Ask to update" (Philz 2026-10-02): GCRPC I.T. asks a tablet to update;
# the app's next report gets update: true and puts a full-width Update bar up.
class AddUpdateRequestToTablets < ActiveRecord::Migration[5.2]
  def change
    add_column :tablets, :update_requested_at, :datetime
    add_column :tablets, :update_requested_by, :string
    add_column :tablets, :update_done_at, :datetime
  end
end
