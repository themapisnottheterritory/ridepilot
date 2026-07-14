# DVIR step 2 — a checklist item in the inspection template.
class VehicleInspectionSerializer
  include FastJsonapi::ObjectSerializer
  set_type :vehicle_inspection
  attributes :description, :category, :phase, :position, :cdl_only, :flagged, :mechanical
end
