class AddRiderToFixedRouteBoardings < ActiveRecord::Migration[7.1]
  # Fare cards, phase 2 (docs/fare-card-design.md). A tap on the bus creates a
  # walk-on for a known rider, so the boarding remembers who and which token.
  # Walk-ons logged by hand keep both nil.
  def change
    add_column :fixed_route_boardings, :customer_id, :integer
    add_column :fixed_route_boardings, :fare_token_id, :integer
    add_index  :fixed_route_boardings, :customer_id
  end
end
