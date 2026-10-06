require 'active_support/concern'

# Use with `include ItineraryCore`
module ItineraryCore
  extend ActiveSupport::Concern

  included do
    #belongs_to :trip
    #belongs_to :run
    belongs_to :address, -> { with_deleted }

    scope :revenue, -> { where.not(trip: nil) }
    scope :deadhead, -> { where(trip: nil) }

    scope :run_begin, -> { where(trip: nil, leg_flag: 0) }
    scope :pickup, -> { where.not(trip: nil).where(leg_flag: 1) }
    scope :dropoff, -> { where.not(trip: nil).where(leg_flag: 2) }
    scope :run_end, ->{ where(trip: nil, leg_flag: 3) }

    def self.clear_times!
      self.where.not("eta is NULL AND travel_time is NULL AND depart_time is NULL").update_all(eta: nil, travel_time: nil, depart_time: nil)
    end

    def prev=(prev_itin)
      @prev = prev_itin
    end

    def prev 
      @prev
    end

    def next=(next_itin)
      @next = next_itin
    end

    def next
      @next
    end

    def is_begin_run?
      leg_flag == 0
    end

    def is_end_run?
      leg_flag == 3
    end

    def is_pickup?
      leg_flag == 1
    end

    def is_dropoff?
      leg_flag == 2
    end

    def label
      case leg_flag
      when 0
        "Start"
      when 3
        "End"
      when 1
        "Pick up #{self.trip.try(:customer).try(:name)}"
      when 2
        "Drop off #{self.trip.try(:customer).try(:name)}"
      end
    end

    def ordinal 
      @ordinal ||= case leg_flag 
      when 0
        0
      when 1..2
        zero_index = (run.manifest_order || []).try(:index, itin_id)
        zero_index ? (zero_index + 1) : -1
      when 3
        run.manifest_order.size + 1
      end
    end

    def scheduled_time
      @scheduled_time ||= time || (leg_flag == 2 ? trip.pickup_time : nil) 
    end

    # scheduled time delta since midnight of day
    def time_diff
      @time_diff ||= time_portion(scheduled_time) 
    end

    def to_address
      @to_address ||= @next.address if @next
    end

    def capacity=(capacity)
      @capacity = capacity
    end

    def capacity
      @capacity
    end

    def ntd_capacity=(ntd_capacity)
      @ntd_capacity = ntd_capacity
    end

    def ntd_capacity
      @ntd_capacity
    end

    def capacity_warning=(capacity_warning)
      @capacity_warning = capacity_warning
    end

    def capacity_warning
      @capacity_warning
    end

    def itin_id 
      case leg_flag 
      when 0 
        "run_begin"
      when 1..2 # Pickup or dropoff
        "trip_#{trip.try(:id)}_leg_#{leg_flag}"
      when 3 
        "run_end"
      end
    end

    def calculate_eta! 
      # previous leg depart_time + travel_time
      self.eta = if @prev && @prev.departure_time && @prev.travel_time
        # actual departure time
        @prev.departure_time + @prev.travel_time.seconds 
      elsif @prev && @prev.depart_time && @prev.travel_time
        # estimated departure time
        @prev.depart_time + @prev.travel_time.seconds 
      else
        time
      end

      update_depart_time

      self.save(validate: false)
    end

    def update_depart_time
      new_time = (self.eta + process_time.to_i.minutes) if self.eta
      ready = ready_time
      self.depart_time = if ready && new_time
        new_time > ready ? new_time : ready
      else
        new_time
      end
    end

    # When the bus can leave this stop at the earliest: a pick-up waits for its
    # rider, who boards no earlier than the pick-up window allows (PickupWindow:
    # the window's start, or the early allowance for a rider who agreed). FTA
    # Circular C 4710.1 §8.5.3. Other stops keep their scheduled time when
    # early isn't allowed, as before.
    def ready_time
      if is_pickup? && trip && (window = PickupWindow.for(trip))
        window.earliest_boarding
      elsif trip && !trip.early_pickup_allowed && time
        time
      end
    end

    # in minutes
    def wait_time
      ready = ready_time
      if ready && eta && ready > eta
        ((ready.to_i - eta.to_i) / 60.to_f).to_i
      else
        0
      end
    end

    # in minutes
    def process_time
      if trip
        leg_flag == 1 ? trip.passenger_load_min : trip.passenger_unload_min
      else 
        0
      end
    end

    def calculate_travel_time!
      if address && to_address && address.geocoded? && to_address.geocoded?
        params = {
          from_lat: address.latitude, 
          from_lon: address.longitude, 
          to_lat: to_address.latitude, 
          to_lon: to_address.longitude, 
          trip_datetime: eta || time
        }

        self.travel_time = TripDistanceDurationProxy.new(ENV['TRIP_PLANNER_TYPE'], params).get_drive_time.to_f
      end
    end

    def time_portion(time)
      (time.to_i - time.beginning_of_day.to_i) if time
    end
  end
end


