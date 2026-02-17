require 'active_support/concern'

module RunCore
  extend ActiveSupport::Concern

  included do
    belongs_to :provider, -> { with_deleted }
    belongs_to :driver, -> { with_deleted }
    belongs_to :vehicle, -> { with_deleted }

    before_save :update_scheduled_time_string

    #validates                 :driver, presence: true
    validates                 :provider, presence: true
    validates                 :name, presence: true
    validates_datetime        :scheduled_start_time, allow_blank: true
    validates_datetime        :scheduled_end_time, after: :scheduled_start_time, allow_blank: true
    validates                 :vehicle, presence: true

    scope :for_paid_driver,        -> { where(paid: true) }
    scope :for_volunteer_driver,   -> { where(paid: false) }
    scope :for_provider,           -> (provider_id) { where(provider_id: provider_id) }
    scope :for_vehicle,            -> (vehicle_id) { where(vehicle_id: vehicle_id) }
    scope :for_driver,             -> (driver_id) { where(driver_id: driver_id) }
    scope :has_scheduled_time,     -> { where.not(scheduled_start_time: nil).where.not(scheduled_end_time: nil) }
 
    scope :starts_before_time, -> (time) do
      query_str = date_agnostic_time_query_str(:scheduled_start_time, :<)
      secs = time.try(:seconds_since_midnight)
      where(query_str, secs)
    end
    
    scope :ends_after_time, -> (time) do
      query_str = date_agnostic_time_query_str(:scheduled_end_time, :>)
      secs = time.try(:seconds_since_midnight)
      where(query_str, secs)
    end

    # Scheduled time overlaps with another start and end time
    scope :time_overlaps_with, -> (start_time, end_time) do
      starts_before_time(end_time)
      .ends_after_time(start_time)
    end
    
    # Overlaps with a repeating run by both DATE and TIME
    scope :overlaps_with_repeating_run, -> (repeating_run) do
      time_overlaps_with(repeating_run.scheduled_start_time, repeating_run.scheduled_end_time)
      .conflicts_with_schedule(repeating_run)
    end

    delegate :name, to: :driver, prefix: :driver, allow_nil: true

    private 

    def update_scheduled_time_string
      self.scheduled_start_time_string = self.scheduled_start_time.try(:to_fs, :time_utc)
      self.scheduled_end_time_string = self.scheduled_end_time.try(:to_fs, :time_utc)

      true
    end
  end

  def cab=(value)
    @cab = value
  end

  def vehicle_name
    vehicle.name if vehicle.present?
  end
  
  def label
    if @cab
      "Cab"
    else
      !name.blank? ? name: "#{vehicle_name}: #{driver.try :name} #{scheduled_start_time.try :strftime, "%I:%M%P"}".gsub( /m$/, "" )
    end
  end
  
  def as_json(options)
    { :id => id, :label => label }
  end
  
  module ClassMethods  
    # Returns a railsy SQL query string based on the given attributes time, regardless of date
    def date_agnostic_time_query_str(column_name, operator=:<)
      col_name_str = "((#{column_name.to_s} AT TIME ZONE 'UTC') AT TIME ZONE '#{Time.zone.now.strftime('%Z')}')"
      "((date_part('hour', #{col_name_str}) * 3600 + " +
        "date_part('minute', #{col_name_str}) * 60 + " +
        "date_part('second', #{col_name_str})) #{operator.to_s} ?)"
    end
  end

end
