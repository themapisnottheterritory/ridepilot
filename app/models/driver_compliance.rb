class DriverCompliance < ApplicationRecord
  include ComplianceCore
  include RecurringComplianceEvent

  has_paper_trail
  
  belongs_to :driver, inverse_of: :driver_compliances
  # A compliance event may be entered by hand: no template, no recurring parent.
  belongs_to :driver_requirement_template, -> { with_deleted }, optional: true
  belongs_to :recurring_driver_compliance, inverse_of: :driver_compliances, optional: true
  
  validates :driver, presence: true
  
  scope :for_driver, -> (driver_id) { where(driver_id: driver_id) }

  # Only used internally, but public for testability
  def self.editable_occurrence_attributes
    [:compliance_date]
  end
  
  # Only used internally, but public for testability
  def is_recurring?
    recurring_driver_compliance.present?
  end
end
