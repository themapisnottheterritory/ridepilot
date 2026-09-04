# A walk-on on a fixed-route run: how many riders of one category boarded at a
# stop (and how many got off), with the fare type. These are the fixed-route
# equivalent of trips and feed unlinked passenger trips on the NTD report.
#
# One tablet submission = one row per rider category with a non-zero count,
# all sharing client_uuid; alighted_count is carried on the first row only.
class FixedRouteBoarding < ApplicationRecord
  acts_as_paranoid
  has_paper_trail

  belongs_to :provider
  belongs_to :run
  belongs_to :fixed_route, optional: true
  belongs_to :stop, class_name: "FixedRouteStop", foreign_key: :fixed_route_stop_id, optional: true
  belongs_to :driver, optional: true
  belongs_to :vehicle, optional: true
  belongs_to :rider_category
  belongs_to :fare_type, optional: true

  validates :client_uuid, :recorded_at, presence: true
  validates :boarded_count, :alighted_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :rider_category_id, uniqueness: { scope: :client_uuid, conditions: -> { where(deleted_at: nil) } }
  validates :fare_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :for_run,        -> (run_id) { where(run_id: run_id) }
  scope :for_route,      -> (fixed_route_id) { where(fixed_route_id: fixed_route_id) }
  scope :recorded_between, -> (from, to) { where(recorded_at: from..to) }
  scope :chronological,  -> { order(:recorded_at, :id) }

  before_validation :snapshot_from_run, on: :create

  # Rows sharing a client_uuid are one tap on the tablet.
  def submission_rows
    self.class.where(client_uuid: client_uuid)
  end

  private

  def snapshot_from_run
    return unless run
    self.provider_id    ||= run.provider_id
    self.fixed_route_id ||= run.fixed_route_id
    self.driver_id      ||= run.driver_id
    self.vehicle_id     ||= run.vehicle_id
    self.stop_name      ||= stop&.name
    self.direction      ||= stop&.direction
    self.recorded_at    ||= Time.current
  end
end
