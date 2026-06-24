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

  # Step 2 — open a RidePilot vehicle_maintenance_event for each defect line item.
  # Idempotent: guarded by maintenance_pushed_at so a re-submit won't duplicate events.
  # Returns the number of maintenance events created.
  def push_defects_to_maintenance!
    return 0 if vehicle.nil? || maintenance_pushed_at.present?

    created = 0
    transaction do
      defects.each do |item|
        insp  = item.vehicle_inspection
        label = [insp&.category, insp&.description].compact.join(" / ").presence || "Inspection item ##{item.vehicle_inspection_id}"
        summary = "DVIR #{phase} defect: #{label}"
        summary += " — #{item.defect_note}" if item.defect_note.present?

        vehicle.vehicle_maintenance_events.create!(
          services_performed: summary,
          service_date:       (submitted_at || certified_at || Time.current).to_date,
          odometer:           odometer
        )
        created += 1
      end
      update_column(:maintenance_pushed_at, Time.current)
    end
    created
  end
end
