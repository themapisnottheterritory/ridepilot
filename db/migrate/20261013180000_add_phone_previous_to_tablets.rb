# The SIM number a tablet reported before its current one, and when it changed:
# a new number means the SIM was swapped (Tablets page, 2026-10-13).
class AddPhonePreviousToTablets < ActiveRecord::Migration[7.1]
  def change
    add_column :tablets, :phone_previous, :string
    add_column :tablets, :phone_changed_at, :datetime
  end
end
