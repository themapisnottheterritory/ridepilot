# DVIR step 2 — one inspection line item result, with any defect photos.
class RunVehicleInspectionSerializer
  include FastJsonapi::ObjectSerializer
  set_type :run_vehicle_inspection
  attributes :vehicle_inspection_id, :status, :defect_note, :checked

  attribute :photo_urls do |object|
    if object.photos.attached?
      object.photos.map { |p| Rails.application.routes.url_helpers.rails_blob_path(p, only_path: true) }
    else
      []
    end
  end
end
