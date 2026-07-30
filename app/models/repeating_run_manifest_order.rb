class RepeatingRunManifestOrder < ApplicationRecord
  belongs_to :repeating_run

  scope :for_wday, -> (wday) { where(wday: wday) }

  serialize :manifest_order, coder: YAML, type: Array

  def delete_trip_manifest!(trip_id)
    unless self.manifest_order.blank? 
      self.manifest_order.delete "trip_#{trip_id}_leg_1"
      self.manifest_order.delete "trip_#{trip_id}_leg_2"
      self.save(validate: false)
    end
  end
end
