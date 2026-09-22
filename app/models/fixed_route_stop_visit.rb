# One published stop on one trip of a fixed-route run, and whether the bus
# stopped there. Written by the tablet (GCRPC Fixed Route), read by the office.
class FixedRouteStopVisit < ApplicationRecord
  STATUSES = %w[served skipped].freeze

  belongs_to :provider
  belongs_to :run
  belongs_to :fixed_route, optional: true
  belongs_to :fixed_route_stop, optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :client_uuid, presence: true, uniqueness: true

  scope :served,  -> { where(status: "served") }
  scope :skipped, -> { where(status: "skipped") }
  scope :chronological, -> { order(:arrived_at, :departed_at, :id) }
end
