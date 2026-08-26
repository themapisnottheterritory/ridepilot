class Driver < ApplicationRecord
  include RequiredFieldValidatorModule
  include Available
  include Inactivateable
  include PublicActivity::Common

  acts_as_paranoid # soft delete

  has_paper_trail

  belongs_to :address, -> { with_deleted }, class_name: 'DriverAddress', foreign_key: 'address_id'
  # Optional by name and by data: it is the driver's SECOND address, and not one
  # of the 51 imported from Shaw has one. Rails 5 made belongs_to required by
  # default, which quietly turned every driver record invalid -- "Alt address
  # must exist" -- so none of them could be saved from the profile screen.
  belongs_to :alt_address, -> { with_deleted }, class_name: 'DriverAddress', foreign_key: 'alt_address_id', optional: true
  belongs_to :provider, -> { with_deleted }
  belongs_to :user, -> { with_deleted }

  has_one :device_pool_driver, dependent: :destroy
  has_one :device_pool, through: :device_pool_driver

  has_one :emergency_contact
  accepts_nested_attributes_for :emergency_contact

  has_many :documents, as: :documentable, dependent: :destroy, inverse_of: :documentable
  has_many :driver_histories, dependent: :destroy, inverse_of: :driver
  has_many :runs, inverse_of: :driver

  # profile photo
  has_one  :photo, class_name: 'Image', as: :imageable, dependent: :destroy, inverse_of: :imageable
  accepts_nested_attributes_for :photo

  # We must specify :delete_all in order to avoid the before_destroy hook. See
  # the RecurringComplianceEvent concern for more details.
  # TODO Look into using `#mark_for_destruction` and `#marked_for_destruction?`
  has_many :driver_compliances, dependent: :delete_all, inverse_of: :driver

  accepts_nested_attributes_for :address, update_only: true
  accepts_nested_attributes_for :alt_address, update_only: true

  validates :address, associated: true, presence: true
  validates :email, format: { with: Devise.email_regexp, allow_blank: true }
  validates :provider, presence: true
  validates :user, presence: true
  validates :user_id, uniqueness: { allow_nil: true, conditions: -> { where(deleted_at: nil) } }
  validates :phone_number, presence: true
  validate  :valid_phone_number
  validates_associated :photo

  before_validation :load_name

  scope :users,         -> { where("drivers.user_id IS NOT NULL") }
  scope :for_provider,  -> (provider_id) { where(provider_id: provider_id) }
  scope :default_order, -> { joins("left outer join users on users.id = drivers.user_id").reorder(Arel.sql("lower(users.last_name)"), Arel.sql("lower(users.first_name)")) }

  after_initialize :set_defaults
  
  def self.unassigned(provider)
    users.for_provider(provider).reject { |driver| driver.device_pool.present? }
  end

  def compliant?(as_of: Date.current)
    driver_compliances.overdue(as_of: as_of).empty?
  end

  # Sums the actual run time hours of all completed runs for this driver
  def run_hours
    runs.this_week.complete.total_scheduled_hours
  end

  def user_name
    user.try(:name) || name
  end

  private

  def set_defaults
    self.active = true if self.active.nil?
  end

  def valid_phone_number
    util = Utility.new
    if phone_number.present?
      errors.add(:phone_number, 'is invalid') unless util.phone_number_valid?(phone_number)
    end

    if alt_phone_number.present?
      errors.add(:alt_phone_number, 'is invalid') unless util.phone_number_valid?(alt_phone_number)
    end
  end

  def load_name
    self.name = self.user.try(:name)
  end

end
