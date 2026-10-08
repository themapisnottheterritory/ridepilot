# A photo of the odometer or a fuel pump, and what the scan model read from it
# (tablet 1.0.34). See ScanReader and Api::V1::Driver::ScansController.
class ReadingScan < ApplicationRecord
  KINDS = %w[odometer pump].freeze

  belongs_to :run, optional: true
  belongs_to :vehicle, optional: true
  belongs_to :driver, optional: true
  belongs_to :vehicle_inspection_report, optional: true
  belongs_to :fuel_log, optional: true
  has_one_attached :photo

  validates :kind, inclusion: { in: KINDS }

  # The driver kept a different number than the scan read.
  def corrected?
    value.present? && accepted_value.present? && value != accepted_value
  end
end
