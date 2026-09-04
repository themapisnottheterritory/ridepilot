# One stop on one direction of a fixed route, in operating order. Synced from
# the authoring tool; the external ids let a re-sync update in place so
# boardings keep pointing at the same row.
class FixedRouteStop < ApplicationRecord
  belongs_to :fixed_route
  has_many :boardings, class_name: "FixedRouteBoarding"

  validates :name, :direction, :external_route_id, :external_stop_id, presence: true
  validates :sequence, numericality: { greater_than_or_equal_to: 0 }

  scope :for_direction, -> (direction) { where(direction: direction) }
  scope :timepoints,    -> { where(timepoint: true) }

  def coordinates?
    latitude.present? && longitude.present?
  end
end
