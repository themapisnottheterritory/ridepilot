# DVIR step 2 — a submitted inspection report header + its line items.
class VehicleInspectionReportSerializer
  include FastJsonapi::ObjectSerializer
  set_type :vehicle_inspection_report
  attributes :phase, :odometer, :lift_cycle_count, :gallons, :safe_to_operate,
             :has_defects, :signature_data, :certified_at, :submitted_at

  belongs_to :run
  belongs_to :vehicle
  has_many :run_vehicle_inspections
end
