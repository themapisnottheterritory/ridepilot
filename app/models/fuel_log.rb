# A bus taking fuel (tablet 1.0.34). See the migration for what goes in it.
class FuelLog < ApplicationRecord
  SOURCES = %w[mid_shift post_trip].freeze
  MAX_GALLONS = 150   # more than any tank in the fleet: a typo

  belongs_to :vehicle
  belongs_to :run, optional: true
  belongs_to :driver, optional: true
  belongs_to :vehicle_inspection_report, optional: true
  has_many :reading_scans, dependent: :nullify

  validates :source, inclusion: { in: SOURCES }
  validates :gallons, numericality: { greater_than: 0, less_than_or_equal_to: MAX_GALLONS }

  scope :recent, -> { order(fueled_at: :desc) }

  def pump_scan
    reading_scans.detect { |s| s.kind == "pump" }
  end

  # Price and total from what the pump photo read, kept only when the gallons
  # the driver kept match the photo (otherwise the money is for another fill).
  def take_cost_from(scan)
    return unless scan&.kind == "pump" && scan.value.present?
    return unless (scan.reading["gallons"].to_f - gallons.to_f).abs < 0.05
    self.price_per_gallon ||= scan.reading["price_per_gallon"]
    self.total_cost ||= scan.reading["total"]
  end

  def self.record_post_trip!(report, scans)
    return if report.phase != "post" || report.gallons.to_f <= 0 || report.vehicle_id.nil?
    log = find_or_initialize_by(vehicle_inspection_report_id: report.id)
    log.assign_attributes(provider_id: report.provider_id, vehicle_id: report.vehicle_id, run_id: report.run_id,
                          driver_id: report.driver_id, source: "post_trip", gallons: report.gallons,
                          odometer: report.odometer, fueled_at: report.submitted_at || Time.current)
    log.take_cost_from(scans.detect { |s| s.kind == "pump" })
    log.save!
    scans.each { |s| s.update_column(:fuel_log_id, log.id) }
    log
  end
end
