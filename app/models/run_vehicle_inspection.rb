class RunVehicleInspection < ApplicationRecord
  belongs_to :run
  belongs_to :vehicle_inspection, -> { with_deleted }
  belongs_to :vehicle_inspection_report, optional: true

  STATUSES = %w[ok defect na].freeze
  validates :status, inclusion: { in: STATUSES }, allow_nil: true

  scope :for_date_range,     -> (from_date, to_date) { where(updated_at: from_date.beginning_of_day..(to_date - 1.day).end_of_day) }
  scope :defects, -> { where(status: "defect") }
end
