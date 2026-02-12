require 'active_support/concern'

module TripCore
  extend ActiveSupport::Concern

  included do
    after_initialize :set_defaults
    before_save :ensure_customer_count_exist
    belongs_to :customer, -> { with_deleted }, validate: false
    belongs_to :dropoff_address,  -> { with_deleted }, class_name: "Address"
    belongs_to :funding_source, -> { with_deleted }, optional: true
    belongs_to :mobility, -> { with_deleted }, optional: true
    belongs_to :pickup_address, -> { with_deleted }, class_name: "Address"
    belongs_to :provider, -> { with_deleted }
    belongs_to :service_level, -> { with_deleted }, optional: true
    belongs_to :trip_purpose, -> { with_deleted }

    delegate :name, to: :service_level, prefix: :service_level, allow_nil: true
    delegate :name, to: :customer, prefix: :customer, allow_nil: true
    delegate :name, to: :trip_purpose, prefix: :trip_purpose, allow_nil: true

    validates :attendant_count, numericality: {greater_than_or_equal_to: 0}
    validates :customer, associated: true, presence: true
    validates :dropoff_address, associated: true, presence: true
    validates :guest_count, numericality: {greater_than_or_equal_to: 0}
    validates :pickup_address, associated: true, presence: true
    validates :trip_purpose_id, presence: true
    validates_datetime :pickup_time, presence: true
    validate :return_trip_later_than_outbound_trip

    validates_datetime :appointment_time, allow_nil: true, on_or_after: :pickup_time, on_or_after_message: "should be no earlier than pickup time", unless: :no_appointment_time?

    accepts_nested_attributes_for :customer

    scope :by_funding_source,  -> (name) { includes(:funding_source).references(:funding_source).where("funding_sources.name = ?", name) }
    scope :by_service_level,   -> (level) { includes(:service_level).references(:service_level).where("service_levels.name = ?", level) }
    scope :by_trip_purpose,    -> (name) { includes(:trip_purpose).references(:trip_purpose).where("trip_purposes.name = ?", name) }
    scope :for_provider,       -> (provider_id) { where(provider_id: provider_id) }
    scope :individual,         -> { joins(:customer).where(customers: {group: false}) }
    scope :not_called_back,    -> { where('called_back_at IS NULL') }

    private

    def no_appointment_time?
      appointment_time.nil?
    end
  end

  def trip_size
    (customer_space_count || 1) + guest_count.to_i + attendant_count.to_i + service_animal_space_count.to_i
  end

  def human_trip_size
    (customer_space_count || 1) + guest_count.to_i + attendant_count.to_i 
  end

  def trip_count
    trip_size
  end

  def is_in_district?
    pickup_address.try(:in_district) && dropoff_address.try(:in_district)
  end

  def is_return?
    direction.try(:to_sym) == :return
  end

  def is_outbound?
    direction.try(:to_sym) == :outbound
  end

  def is_linked?
    (is_return? && outbound_trip) || (is_outbound? && return_trip)
  end

  module ClassMethods
  end

  private

  def set_defaults
    self.customer_space_count = 1 if self.respond_to?(:customer_space_count) && self.customer_space_count.nil?
    self.guest_count = 0 if self.respond_to?(:guest_count) && self.guest_count.nil?
    self.attendant_count = 0 if self.respond_to?(:attendant_count) && self.attendant_count.nil?
    self.service_animal_space_count = 0 if self.respond_to?(:service_animal_space_count) && self.service_animal_space_count.nil?
    
    if self.respond_to?(:passenger_load_min) && self.passenger_load_min.nil?
      if self.customer
        self.passenger_load_min = self.customer.passenger_load_min
      elsif self.provider
        self.passenger_load_min = self.provider.passenger_load_min
      else
        self.passenger_load_min = Provider::DEFAULT_PASSENGER_LOAD_MIN
      end
    end
    
    if self.respond_to?(:passenger_unload_min) && self.passenger_unload_min.nil?
      if self.customer
        self.passenger_unload_min = self.customer.passenger_unload_min
      elsif self.provider
        self.passenger_unload_min = self.provider.passenger_unload_min
      else
        self.passenger_unload_min = Provider::DEFAULT_PASSENGER_UNLOAD_MIN
      end
    end

    if self.respond_to?(:early_pickup_allowed) && self.early_pickup_allowed.nil?
      self.early_pickup_allowed = self.is_outbound? 
    end
  end

  def ensure_customer_count_exist
    # use default 1 for the case of non-configured customer capacity
    if self.respond_to?(:customer_space_count) && self.customer_space_count.to_i == 0
      self.customer_space_count = 1
    end

    true
  end

  def return_trip_later_than_outbound_trip
    if is_linked?
      if is_outbound? && appointment_time
        errors.add(:base, TranslationEngine.translate_text(:outbound_trip_dropoff_time_no_later_than_return_trip_pickup_time)) if appointment_time > return_trip.pickup_time
      elsif is_return? && pickup_time && outbound_trip.appointment_time
        errors.add(:base, TranslationEngine.translate_text(:return_trip_pickup_time_no_earlier_than_outbound_trip_dropoff_time)) if pickup_time < outbound_trip.appointment_time
      end
    end
  end
end
