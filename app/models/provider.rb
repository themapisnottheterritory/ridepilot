class Provider < ApplicationRecord
  include PublicActivity::Common
  include Operatable
  has_paper_trail
  
  acts_as_paranoid # soft delete
  
  serialize :fields_required_for_run_completion, Array

  after_initialize :set_defaults

  has_many :addresses, class_name: 'ProviderCommonAddress', :dependent => :nullify
  has_many :device_pools, :dependent => :destroy
  has_many :drivers, :dependent => :destroy
  has_many :monthlies, :dependent => :destroy
  has_many :provider_reports
  has_many :recurring_driver_compliances, :dependent => :destroy
  has_many :recurring_vehicle_maintenance_compliances, :dependent => :destroy
  has_many :reports, through: :provider_reports
  has_many :roles, :dependent => :destroy
  has_many :users, :through => :roles
  has_many :vehicles, :dependent => :destroy
  has_many :runs
  has_many :repeating_runs
  has_many :driver_requirement_templates, :dependent => :destroy
  has_many :documents, as: :documentable, dependent: :destroy, inverse_of: :documentable
  has_many :vehicle_inspections, :dependent => :destroy

  has_one :address_upload_flag

  belongs_to :fare, optional: true

  belongs_to :business_address, -> { with_deleted }, class_name: 'ProviderBusinessAddress', foreign_key: 'business_address_id', optional: true
  belongs_to :mailing_address, -> { with_deleted }, class_name: 'ProviderMailingAddress', foreign_key: 'mailing_address_id', optional: true

  accepts_nested_attributes_for :business_address, update_only: true
  accepts_nested_attributes_for :mailing_address, update_only: true

  has_attached_file :logo, :styles => { :small => "150x150>" }
  
  REIMBURSEMENT_ATTRIBUTES = [
    :oaa3b_per_ride_reimbursement_rate,
    :ride_connection_per_ride_reimbursement_rate,
    :trimet_per_ride_reimbursement_rate,
    :stf_van_per_ride_reimbursement_rate,
    :stf_taxi_per_ride_administrative_fee,
    :stf_taxi_per_ride_ambulatory_load_fee,
    :stf_taxi_per_ride_wheelchair_load_fee,
    :stf_taxi_per_mile_ambulatory_reimbursement_rate,
    :stf_taxi_per_mile_wheelchair_reimbursement_rate
  ]

  # default value of advance_day_scheduling
  DEFAULT_ADVANCE_DAY_SCHEDULING = 21
  # default value of eligible_age
  DEFAULT_ELIGIBLE_AGE = 65
  # default load & unload time in minutes
  DEFAULT_PASSENGER_LOAD_MIN = 5
  DEFAULT_PASSENGER_UNLOAD_MIN = 5
  
  validates :name, :uniqueness => { :case_sensitive => false, conditions: -> { where(deleted_at: nil)} }, :length => { :minimum => 2 }
  normalize_attribute :name, :with => [ :strip ]
  
  validates_numericality_of :oaa3b_per_ride_reimbursement_rate,               :greater_than => 0, :allow_blank => true
  validates_numericality_of :ride_connection_per_ride_reimbursement_rate,     :greater_than => 0, :allow_blank => true
  validates_numericality_of :trimet_per_ride_reimbursement_rate,              :greater_than => 0, :allow_blank => true
  validates_numericality_of :stf_van_per_ride_reimbursement_rate,             :greater_than => 0, :allow_blank => true
  validates_numericality_of :stf_taxi_per_ride_administrative_fee,            :greater_than => 0, :allow_blank => true
  validates_numericality_of :stf_taxi_per_ride_ambulatory_load_fee,           :greater_than => 0, :allow_blank => true
  validates_numericality_of :stf_taxi_per_ride_wheelchair_load_fee,           :greater_than => 0, :allow_blank => true
  validates_numericality_of :stf_taxi_per_mile_ambulatory_reimbursement_rate, :greater_than => 0, :allow_blank => true
  validates_numericality_of :stf_taxi_per_mile_wheelchair_reimbursement_rate, :greater_than => 0, :allow_blank => true
  validates_attachment      :logo,
    size: {:less_than => 2.gigabytes}, 
    # prevent content-type spoofing:
    content_type: {:content_type => /\Aimage/},
    file_name: {:matches => [/png\Z/, /gif\Z/, /jpe?g\Z/], allow_blank: true}
  # How many days in advance to create subscription trips/runs
  validates_numericality_of :advance_day_scheduling, :greater_than => 0, :allow_blank => true 
  validate  :valid_phone_number

  validates_numericality_of :driver_availability_min_hour
  validates_numericality_of :driver_availability_max_hour, :greater_than => :driver_availability_min_hour
  
  after_initialize :init

  scope :active, -> { where("inactivated_date is NULL") }
  scope :inactive, -> { where("inactivated_date is not NULL") }
  scope :customer_sharable, -> { where("customer_nonsharable is NULL or customer_nonsharable != ?", true) }

  def init
    self.scheduling = true if new_record?
  end

  def address_upload_flag
    super || AddressUploadFlag.create(provider: self)
  end

  # Phase II J.2
  # TODO: To be eliminated
  def min_trip_time_gap_in_mins
    30
  end

  def active?
    !inactivated_date
  end

  def inactivate!(reason)
    self.inactivated_date = Date.today 
    self.inactivated_reason = reason
    self.save(validate: false)
  end

  def reactivate!
    self.inactivated_date = nil 
    self.inactivated_reason = nil
    self.save(validate: false)
  end

  def check_age_eligible(age)
    if age.present? && (eligible_age || DEFAULT_ELIGIBLE_AGE) <= age
      true 
    else
      false
    end
  end

  def get_advance_day_scheduling
    advance_day_scheduling || DEFAULT_ADVANCE_DAY_SCHEDULING
  end
  
  # Returns true if the passed date falls within the advance scheduling window
  def scheduler_window_covers?(date)
    date < (Date.today + get_advance_day_scheduling.days)
  end

  # has admin or system_admin
  def has_admin?
    roles.admin_and_aboves.any?
  end
  
  # points at the document with the description "Approved Vendor List"
  def vendor_list
    documents.find_by(description: "Approved Vendor List")
  end
  
  # pass a file object and will replace the vendor_list with that file
  def update_vendor_list(file)
    old_vendor_list = vendor_list
    new_vendor_list = documents.build(description: "Approved Vendor List", document: file)
    if new_vendor_list.valid?
      old_vendor_list.delete if old_vendor_list
      new_vendor_list.save
      documents.reload
    else
      documents.reload
      return false
    end
  end
  
  # removes the vendor list associated with the provider
  def remove_vendor_list
    documents.delete(vendor_list)
    return self.save
  end

  private

  def set_defaults
    self.advance_day_scheduling            = DEFAULT_ADVANCE_DAY_SCHEDULING if advance_day_scheduling.nil?
    self.passenger_load_min                = DEFAULT_PASSENGER_LOAD_MIN if self.passenger_load_min.nil?
    self.passenger_unload_min              = DEFAULT_PASSENGER_UNLOAD_MIN if self.passenger_unload_min.nil?
    self.very_early_arrival_threshold_min  = 15 if self.very_early_arrival_threshold_min.nil?
    self.early_arrival_threshold_min       = 5 if self.early_arrival_threshold_min.nil?
    self.late_arrival_threshold_min        = 5 if self.late_arrival_threshold_min.nil?
    self.very_late_arrival_threshold_min   = 15 if self.very_late_arrival_threshold_min.nil?
  end

  def valid_phone_number
    util = Utility.new
    if phone_number.present?
      errors.add(:phone_number, 'is invalid') unless util.phone_number_valid?(phone_number)
    end

    if alt_phone_number.present?
      errors.add(:alt_phone_number, 'is invalid') unless util.phone_number_valid?(alt_phone_number)
    end

    if primary_contact_phone_number.present?
      errors.add(:primary_contact_phone_number, 'is invalid') unless util.phone_number_valid?(primary_contact_phone_number)
    end
  end
end
