module DispatchHelper

  # used in dispatch screen for internal manifest display
  def get_itineraries(run, is_recurring = false, recurring_dispatch_wday = nil)
    return [] unless run

    itins = []

    # get trips/repeating_trips
    trips = if is_recurring
      RepeatingTrip.where(id: run.weekday_assignments.for_wday(recurring_dispatch_wday).pluck(:repeating_trip_id))
    else
      run.trips
    end

    # vehicle capacity
    if run.vehicle && run.vehicle.vehicle_type
      vehicle_capacities = []
      run.vehicle.vehicle_type.vehicle_capacity_configurations.each do |config|
        vehicle_capacities << config.vehicle_capacities.pluck(:capacity_type_id, :capacity).to_h
      end
    end

    trips_table_name = is_recurring ? "repeating_trips" : "trips"
    trip_capacities = get_trip_capacities(trips, trips_table_name)

    # add itinerary specific data
    itins = is_recurring ? run.sorted_itineraries(true, recurring_dispatch_wday) : run.sorted_itineraries(true)
    # default occupancy by capacity type
    occupancy = {}
    CapacityType.by_provider(current_provider).pluck(:id).each do |c_id|
      occupancy[c_id] = 0
    end

    # the occupancy change in each itinerary
    delta = nil
    # PickUp: add (delta_unit = 1), DropOff: subtract (delta_unit = -1)
    delta_unit = 1 
    
    itins.each do |itin|
      trip = itin.trip

      # calculate latest occupancy based on the change in previous leg
      if delta && !delta.blank?
        occupancy.merge!(delta) { |k, a_value, b_value| a_value + delta_unit * b_value }
      end
      # save occupancy snapshot
      itin.capacity = occupancy.dup

      # check if trip capacity > vehicle capacity
      itin.capacity_warning = false
      if vehicle_capacities && vehicle_capacities.any?
        has_enough_capacity = false
        vehicle_capacities.each do |cap_data|
          capacity_met = true
          occupancy.each do |c_id, val|
            if cap_data[c_id].to_i < val
              capacity_met = false
              break 
            end
          end

          if capacity_met
            has_enough_capacity = true
            break
          end
        end
        itin.capacity_warning = true if !has_enough_capacity
      else 
        itin.capacity_warning = true
      end

      # log the occupancy change in this leg for occupancy calculation in next leg
      if TripResult::NON_DISPATCHABLE_CODES.include?(trip.try(:trip_result).try(:code))
        delta = nil
        delta_unit = 0
      elsif itin.leg_flag == 1
        delta = trip_capacities[trip.id]
        delta_unit = 1
      elsif itin.leg_flag == 2
        delta = trip_capacities[trip.id]
        delta_unit = -1
      end
    end

    itins
  end

  # use public_itinerary data and get associated occupancy etc
  # used in manifest report
  # The run's working stops in manifest order, for printing a manifest that
  # hasn't been published: trip stops only, and like the published list,
  # without the drop-off of a cancelled or turned-down trip.
  def draft_manifest_itineraries(run)
    get_itineraries(run).select { |itin| itin.trip && [1, 2].include?(itin.leg_flag) }.reject do |itin|
      itin.leg_flag == 2 && TripResult::NON_DISPATCHABLE_CODES.include?(itin.trip.trip_result&.code)
    end
  end

  def get_public_itineraries(run, trip_only = false)
    return [] unless run

    itins = []
    
    # fetch public itinerary and associated trips
    public_itins = run.public_itineraries
    exclude_leg_ids = Itinerary.where(id: public_itins.pluck(:itinerary_id)).dropoff
      .joins(trip: :trip_result).where(trip_results: {
        code: TripResult::NON_DISPATCHABLE_CODES
        }).pluck(:id).uniq
    public_itins = public_itins.joins(:itinerary).where.not(itineraries: {id: exclude_leg_ids})
    trips = Trip.unscoped.where(id: public_itins.joins(:itinerary).pluck(:trip_id).uniq)

    # vehicle capacity
    if run.vehicle && run.vehicle.vehicle_type
      vehicle_capacities = []
      run.vehicle.vehicle_type.vehicle_capacity_configurations.each do |config|
        vehicle_capacities << config.vehicle_capacities.pluck(:capacity_type_id, :capacity).to_h
      end
    end

    trip_capacities = get_trip_capacities(trips)

    # default occupancy by capacity type
    occupancy = {}
    CapacityType.by_provider(current_provider).pluck(:id).each do |c_id|
      occupancy[c_id] = 0
    end

    # the occupancy change in each itinerary
    delta = nil
    # PickUp: add (delta_unit = 1), DropOff: subtract (delta_unit = -1)
    delta_unit = 1 
    
    public_itins.each do |public_itin|
      itin = public_itin.itinerary
      trip = itin.trip

      next if trip_only && !trip

      # calculate latest occupancy based on the change in previous leg
      if delta && !delta.blank?
        occupancy.merge!(delta) { |k, a_value, b_value| a_value + delta_unit * b_value }
      end
      # save occupancy snapshot
      itin.capacity = occupancy.dup

      # check if trip capacity > vehicle capacity
      itin.capacity_warning = false
      if vehicle_capacities && vehicle_capacities.any?
        has_enough_capacity = false
        vehicle_capacities.each do |cap_data|
          capacity_met = true
          occupancy.each do |c_id, val|
            if cap_data[c_id].to_i < val
              capacity_met = false
              break 
            end
          end

          if capacity_met
            has_enough_capacity = true
            break
          end
        end
        itin.capacity_warning = true if !has_enough_capacity
      else 
        itin.capacity_warning = true
      end

      # log the occupancy change in this leg for occupancy calculation in next leg
      if TripResult::NON_DISPATCHABLE_CODES.include?(trip.try(:trip_result).try(:code))
        delta = nil
        delta_unit = 0
      elsif itin.leg_flag == 1
        delta = trip_capacities[trip.id]
        delta_unit = 1
      elsif itin.leg_flag == 2
        delta = trip_capacities[trip.id]
        delta_unit = -1
      end

      itins << itin
    end

    itins
  end

  def get_trip_capacities(trips, trip_table_name = "trips")
    # system mobility capacity configurations
    mobility_capacities = {}
    MobilityCapacity.has_capacity.each do |c|
      mobility_capacities[[c.host_id, c.capacity_type_id]] = c.capacity
    end

    capacity_type_ids = CapacityType.by_provider(current_provider).pluck(:id)

    # trips capacities
    trip_capacities = {}
    trips.joins(:ridership_mobilities)
      .where("ridership_mobility_mappings.capacity > 0")
      .group("#{trip_table_name}.id", "ridership_mobility_mappings.mobility_id")
      .sum("ridership_mobility_mappings.capacity").each do |k, capacity|

      trip_id = k[0]
      trip_capacities[trip_id] = {} unless trip_capacities.has_key?(trip_id)
      trip_capacity = trip_capacities[trip_id]
      mobility_id = k[1]

      capacity_type_ids.each do |c_id|
        val = trip_capacity[c_id] || 0
        val += capacity * mobility_capacities[[mobility_id, c_id]].to_i

        trip_capacity[c_id] = val
      end
    end

    trip_capacities
  end

  # used in CAD
  def get_itin_occupancy(run, itin_id)
    return unless run && itin_id

    # fetch public itinerary and associated trips
    public_itins = run.public_itineraries
    trips = Trip.unscoped.where(id: public_itins.joins(:itinerary).pluck(:trip_id).uniq)

    trip_capacities = get_trip_capacities(trips)

    # default occupancy by capacity type
    occupancy = {}
    CapacityType.by_provider(current_provider).pluck(:id).each do |c_id|
      occupancy[c_id] = 0
    end

    # the occupancy change in each itinerary
    delta = nil
    # PickUp: add (delta_unit = 1), DropOff: subtract (delta_unit = -1)
    delta_unit = 1 
    itin_occupancy = nil
    finished_itin_matched = false
    public_itins.each do |public_itin|
      itin = public_itin.itinerary
      # calculate latest occupancy based on the change in previous leg
      if delta && !delta.blank?
        occupancy.merge!(delta) { |k, a_value, b_value| a_value + delta_unit * b_value }
      end

      # return updated occupancy for the match itin that is finished
      if finished_itin_matched
        itin_occupancy = occupancy.dup
        break 
      end

      # if itin match found
      if itin.itin_id == itin_id 
        # if not finished, then return current occupancy
        if !itin.finish_time
          itin_occupancy = occupancy.dup 
          break
        else 
          # if finished, flag it, return next itin's occupancy
          finished_itin_matched = true
        end
      end

      trip = itin.trip
      # log the occupancy change in this leg for occupancy calculation in next leg
      if TripResult::NON_DISPATCHABLE_CODES.include?(trip.try(:trip_result).try(:code))
        delta = nil
        delta_unit = 0
      elsif itin.leg_flag == 1
        delta = trip_capacities[trip.id]
        delta_unit = 1
      elsif itin.leg_flag == 2
        delta = trip_capacities[trip.id]
        delta_unit = -1
      end
    end

    itin_occupancy
  end

  def run_summary(run)
    if run
      trip_count = run.trips.count
      trips_part = if trip_count == 0
        "No trip" 
      elsif trip_count == 1
        "1 trip"
      else
        "#{trip_count} trips"
      end

      vehicle = run.vehicle
      if vehicle 
        vehicle_overdue_check = get_vehicle_warnings(vehicle, run)
        vehicle_part = "<span class='#{vehicle_overdue_check[:class_name]}' title='#{vehicle_overdue_check[:tips]}'>Vehicle: #{vehicle.try(:name) || '(empty)'}</span>"
      else
        vehicle_part = "<span>Vehicle: (empty)</span>"
      end

      driver = run.driver
      if driver 
        driver_overdue_check = get_driver_warnings(driver, run)
        driver_part = "<span class='#{driver_overdue_check[:class_name]}' title='#{driver_overdue_check[:tips]}'>Driver: #{driver.try(:user_name) || '(empty)'}</span>"
      else
        driver_part = "<span>Driver: (empty)</span>"
      end

      run_time_part = if !run.scheduled_start_time && !run.scheduled_end_time
        "Run time: (not specified)"
      else
        "Run Time: #{format_time_for_listing(run.scheduled_start_time)} - #{format_time_for_listing(run.scheduled_end_time)}"
      end
      
      [vehicle_part, driver_part, run_time_part, trips_part].join(', ')
    end
  end

  def recurring_run_summary(run, wday = Date.today.wday)
    if run
      trip_count = run.weekday_assignments.for_wday(wday).count
      trips_part = if trip_count == 0
        "No trip" 
      elsif trip_count == 1
        "1 trip"
      else
        "#{trip_count} trips"
      end

      vehicle = run.vehicle
      if vehicle 
        vehicle_overdue_check = get_vehicle_warnings(vehicle, run)
        vehicle_part = "<span class='#{vehicle_overdue_check[:class_name]}' title='#{vehicle_overdue_check[:tips]}'>Vehicle: #{vehicle.try(:name) || '(empty)'}</span>"
      else
        vehicle_part = "<span>Vehicle: (empty)</span>"
      end

      driver = run.driver
      if driver 
        driver_overdue_check = get_driver_warnings(driver, run)
        driver_part = "<span class='#{driver_overdue_check[:class_name]}' title='#{driver_overdue_check[:tips]}'>Driver: #{driver.try(:user_name) || '(empty)'}</span>"
      else
        driver_part = "<span>Driver: (empty)</span>"
      end

      run_time_part = if !run.scheduled_start_time && !run.scheduled_end_time
        "Run time: (not specified)"
      else
        "Run Time: #{format_time_for_listing(run.scheduled_start_time)} - #{format_time_for_listing(run.scheduled_end_time)}"
      end
      
      [vehicle_part, driver_part, run_time_part, trips_part].join(', ')
    end
  end

  def slack_color(slack_time)
    return unless slack_time

    very_early_threshold = current_provider.very_early_arrival_threshold_min || 15 
    early_threshold = current_provider.early_arrival_threshold_min || 5 
    late_threshold = current_provider.late_arrival_threshold_min || 5 
    very_late_threshold = current_provider.very_late_arrival_threshold_min || 15 

    if slack_time > 0
      if  very_late_threshold <= slack_time
        "#ff0000"
      elsif late_threshold <= slack_time
        "#ffff00"
      else
        "#aaafaa"
      end
    else
      slack_time = slack_time * -1
      if  very_early_threshold <= slack_time
        "#3c763d"
      elsif early_threshold <= slack_time
        "#dff0d8"
      else
        "#aaafaa"
      end
    end
       
  end

  def format_slack_tooltip(itin)
    return unless itin 

    tooltip = ""
    if itin[:leg_flag] == 0
      tooltip += "leaving garage "
    elsif itin[:leg_flag] == 1
      tooltip += "pick up "
    elsif itin[:leg_flag] == 2
      tooltip += "drop off "
    elsif itin[:leg_flag] == 3
      tooltip += "going back to garage "
    end

    unless itin[:customer].blank?
      tooltip += itin[:customer]
    end

    slack_time = itin[:slack_time]
    if slack_time < 0
      tooltip += " (#{slack_time * -1} minutes early)"
    elsif slack_time > 0
      tooltip += " (#{slack_time} minutes late)"
    else
      tooltip += " (on time)"
    end

    tooltip

  end

  private

  def time_portion(time)
    (time - time.beginning_of_day) if time
  end

end