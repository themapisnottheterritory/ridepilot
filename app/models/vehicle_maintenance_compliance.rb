class VehicleMaintenanceCompliance < ApplicationRecord
  include DocumentAssociable
  include ComplianceEvent
  include RecurringComplianceEvent
  has_paper_trail

  DUE_TYPES = [:date, :mileage, :both].freeze
  
  belongs_to :vehicle, inverse_of: :vehicle_maintenance_compliances
  # A compliance event may be entered by hand: no recurring parent, no schedule.
  belongs_to :recurring_vehicle_maintenance_compliance, inverse_of: :vehicle_maintenance_compliances, optional: true
  belongs_to :vehicle_maintenance_schedule, optional: true
  
  validates :vehicle, presence: true
  validates :due_type, inclusion: { in: DUE_TYPES.map(&:to_s) }
  validates :due_date, presence: { if: :due_date_required? }
  validates_date :due_date, allow_blank: true
  validates :due_mileage, presence: { if: :due_mileage_required? }
  validates :due_mileage, numericality: { only_integer: true, greater_than: 0, allow_blank: true }
  validates :compliance_date, presence: { if: -> { self.compliance_mileage.present? } }
  validates :compliance_mileage, presence: { if: -> { self.compliance_date.present? } }, numericality: { only_integer: true, greater_than_or_equal_to: 0, allow_blank: true }
  
  scope :for_vehicle, -> (vehicle_id) { where(vehicle_id: vehicle_id) }
  #scope :default_order, -> { order("due_date IS NOT NULL, due_date, due_mileage") }
  scope :default_order, -> { order(Arel.sql("due_date IS NOT NULL"), :due_date, :due_mileage) }
  
  # NOTE These 2 scopes rely on data from vehicles and runs
  # RADAR change to pure SQL if this routinely operates on large sets
  scope :overdue, -> (as_of: Date.current) { where(id: incomplete.select{ |r| r.overdue?(as_of: as_of) }.collect(&:id)) }
  scope :due_soon, -> (as_of: Date.current, through: nil, within_mileage: 500) { where(id: incomplete.select{ |r|  r.overdue?(as_of: as_of..(through || as_of + 6.days), mileage: r.vehicle_odometer_reading..(r.vehicle_odometer_reading + within_mileage)) }.collect(&:id)) }
  
  after_initialize :set_defaults

  # Extend the #overdue? method from the ComplianceEvent concern
  def overdue_with_due_type?(as_of: Date.current, mileage: vehicle_odometer_reading)
    case due_type.to_sym
    when :date
      overdue_without_due_type? as_of: as_of
    when :mileage
      is_over_due_mileage? mileage
    when :both
      overdue_without_due_type?(as_of: as_of) && is_over_due_mileage?(mileage)
    end
  end
  alias_method :overdue_without_due_type?, :overdue?
  alias_method :overdue?, :overdue_with_due_type?
  
  def vehicle_odometer_reading
    vehicle.last_odometer_reading
  end
  
  # Only used internally, but public for testability
  def self.editable_occurrence_attributes
    [:compliance_date, :compliance_mileage]
  end

  def self.has_overdue?(as_of: Date.current)
    self.incomplete.each do |r|
      if r.overdue?(as_of: as_of)
        return true
      end
    end

    false
  end
  
  # Only used internally, but public for testability
  def is_recurring?
    recurring_vehicle_maintenance_compliance.present?
  end

  private

  def set_defaults
    self.due_type ||= "mileage"
  end
  
  def is_over_due_mileage?(mileage)
    if mileage.is_a? Range
      mileage.include? due_mileage
    else
      mileage > due_mileage
    end
  end
  
  def due_date_required?
    [:both, :date].include? due_type.try(:to_sym)
  end
  
  def due_mileage_required?
    [:both, :mileage].include? due_type.try(:to_sym)
  end
end
