# Each tablet's own Verizon number (MTN) on the Tablets page (Ron, 2026-10-11).
# phone_number is what the SIM reports (Demand Response 1.0.41+); phone_typed is
# what GCRPC I.T. typed from Settings > About tablet > Status. Columns, not
# `info`: each report replaces `info`, and the Fixed Route app doesn't send it.
class AddPhoneNumbersToTablets < ActiveRecord::Migration[7.1]
  def change
    add_column :tablets, :phone_number, :string
    add_column :tablets, :phone_typed, :string
  end
end
