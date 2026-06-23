# DVIR step 1 — report header for a driver's pre/post-trip inspection.
# One report per (run, phase). Line items are RunVehicleInspection rows
# pointing back via vehicle_inspection_report_id.
class VehicleInspectionReport < ApplicationRecord
  PHASES = %w[pre post].freeze

  belongs_to :run,      optional: true
  belongs_to :provider, optional: true
  belongs_to :vehicle,  optional: true
  belongs_to :driver,   optional: true

  has_many :run_vehicle_inspections, dependent: :nullify

  validates :phase, inclusion: { in: PHASES }

  scope :recent, -> { order(submitted_at: :desc) }

  def defects
    run_vehicle_inspections.where(status: "defect")
  end

  # Recompute the defect flag from the line items (call after building items).
  def refresh_defects!
    update_column(:has_defects, run_vehicle_inspections.where(status: "defect").exists?)
  end

  # Step 2 will use this to open RidePilot vehicle_maintenance_events for each defect.
  # def push_defects_to_maintenance!; ...; end
end
