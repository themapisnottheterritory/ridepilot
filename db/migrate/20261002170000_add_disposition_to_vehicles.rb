# Tony (fleet), 2026-10-02: mark a bus as being moved to disposition, then record how it
# left the fleet (the facts FTA asks for on a grant-funded vehicle). Vehicle#disposition.
class AddDispositionToVehicles < ActiveRecord::Migration[5.2]
  def change
    add_column :vehicles, :disposition_status, :string      # nil, "pending" (moved to disposition), "disposed"
    add_column :vehicles, :disposition_started_on, :date
    add_column :vehicles, :disposed_on, :date
    add_column :vehicles, :disposition_method, :string
    add_column :vehicles, :disposition_odometer, :integer
    add_column :vehicles, :disposition_proceeds, :decimal, precision: 10, scale: 2
    add_column :vehicles, :disposition_notes, :text
  end
end
