# DVIR step 1 — additive, reversible. Extends RidePilot's existing
# vehicle_inspections / run_vehicle_inspections and adds a report header.
# Apply on a branch, after a DB backup:  rails db:migrate
class CreateDvirInspectionModel < ActiveRecord::Migration[7.1]
  def change
    # --- 1) Item library: section, phase, ordering, CDL/air-brake flag ---
    add_column :vehicle_inspections, :category, :string                         # e.g. "Brakes", "Safety"
    add_column :vehicle_inspections, :phase,    :string,  default: "both", null: false  # "pre" | "post" | "both"
    add_column :vehicle_inspections, :position, :integer                        # display order
    add_column :vehicle_inspections, :cdl_only, :boolean, default: false, null: false   # air-brake/CDL-only item

    # --- 2) Report header: one row per run + phase ---
    create_table :vehicle_inspection_reports do |t|
      t.references :run,      foreign_key: true, null: true
      t.references :provider, foreign_key: true, null: true
      t.references :vehicle,  foreign_key: true, null: true
      t.references :driver,   foreign_key: true, null: true
      t.string   :phase,           null: false                # "pre" | "post"
      t.integer  :odometer
      t.integer  :lift_cycle_count                            # wheelchair lift cycle counter reading
      t.decimal  :gallons, precision: 8, scale: 2             # fuel purchased (post-trip)
      t.boolean  :safe_to_operate                             # the IS / IS NOT certification
      t.boolean  :has_defects, default: false, null: false
      t.text     :signature_data                              # PNG data-URL (Active Storage photos come in step 2)
      t.datetime :certified_at
      t.datetime :submitted_at
      t.timestamps
    end
    add_index :vehicle_inspection_reports, [:vehicle_id, :phase]
    add_index :vehicle_inspection_reports, :submitted_at

    # --- 3) Per-item result: status + free-text note + link to its report ---
    add_column :run_vehicle_inspections, :status,      :string, default: "ok", null: false  # "ok" | "defect" | "na"
    add_column :run_vehicle_inspections, :defect_note, :text
    add_reference :run_vehicle_inspections, :vehicle_inspection_report, foreign_key: true, null: true
  end
end
