# a wrapper over public_activity gem
class TrackerActionLog < PublicActivity::Activity

  scope :for, -> (trackable) { where(trackable: trackable) }

  def self.create_trip(trip, user)
    if trip
      trip.create_activity :created, owner: user 
      #if trip.run.present?
      #  TrackerActionLog.trips_added_to_run(trip.run, [trip], user)
      #end
    end
  end

  def self.create_run(run, user)
    if run
      run.create_activity :created, owner: user 
    end
  end

  def self.create_return_trip(return_trip, user)
    if return_trip
      return_trip.create_activity :return_created, owner: user 
      outbound_trip = return_trip.outbound_trip
      outbound_trip.create_activity :create_return, owner: user if outbound_trip

      #if return_trip.run.present?
      #  TrackerActionLog.trips_added_to_run(return_trip.run, [return_trip], user)
      #end
    end
  end

  def self.cancel_or_turn_down_trip(trip, user)
    if trip && trip.is_cancelled_or_turned_down?
      action = trip.trip_result.turned_down? ? :trip_turned_down : :trip_cancelled
      trip.create_activity action, owner: user, params: {
        trip_result: trip.trip_result.try(:name), 
        reason: trip.result_reason
      }
    end
  end

  def self.create_subscription_trip(trip, user)
    if trip 
      trip.create_activity :subscription_created, owner: user
    end
  end

  def self.update_subscription_trip(trip, user, changes, previous_schedule = nil)
    if trip
      params = {}
      changes.each do |k, change|
        case k
        when 'pickup_time'
          if !compare_time_only(change[0], change[1])
            params["Pickup Time"] = [change[0].try(:strftime,'%I:%M%P'), trip.pickup_time.strftime('%I:%M%P')]
          end
        when 'appointment_time'
          if change[0].nil? || change[1].nil? || !compare_time_only(change[0], change[1])
            params["Appointment Time"] = [change[0].try(:strftime,'%I:%M%P'), trip.appointment_time.try(:strftime, '%I:%M%P')]
          end
        when 'pickup_address_id'
          old_address = Address.find_by_id(change[0])
          new_address = trip.pickup_address
          params["Pickup Address"] = [old_address.try(:address_text), new_address.try(:address_text)]
        when 'dropoff_address_id'
          old_address = Address.find_by_id(change[0])
          new_address = trip.dropoff_address
          params["Dropoff Address"] = [old_address.try(:address_text), new_address.try(:address_text)]
        when 'customer_id'
          old_customer = Customer.find_by_id(change[0])
          new_customer = trip.customer
          params["Customer"] = [old_customer.try(:name), new_customer.try(:name)] 
        when 'trip_purpose_id'
          old_purpose = TripPurpose.find_by_id(change[0])
          new_purpose = trip.trip_purpose
          params["Trip Purpose"] = [old_purpose.try(:name), new_purpose.try(:name)]
        when 'mobility_id'
          old_mobility = Mobility.find_by_id(change[0])
          new_mobility = trip.mobility
          params["Mobility"] = [old_mobility.try(:name), new_mobility.try(:name)]
        when 'guest_count'
          params["Guests"] = change
        when 'attendant_count'
          params["Attendants"] = change
        when 'service_animal_count'
          params["Service Animal"] = change
        when 'start_date'
          params["Start Date"] = [change[0].try(:strftime, "%B %d, %Y"), trip.start_date.try(:strftime, "%B %d, %Y")]
        when 'end_date'
          params["End Date"] = [change[0].try(:strftime, "%B %d, %Y"), trip.end_date.try(:strftime, "%B %d, %Y")]
        end
      end

      previous_schedule_desc = previous_schedule.try(:to_s) rescue ""
      current_schedule_desc = trip.schedule.try(:to_s) rescue ""
      if previous_schedule_desc != current_schedule_desc
        params["Schedule"] = [previous_schedule_desc, current_schedule_desc]
      end

      trip.create_activity :subscription_updated, owner: user, params: params unless params.blank?
    end
  end

  def self.create_subscription_run(run, user)
    if run 
      run.create_activity :subscription_created, owner: user
    end
  end

  def self.update_subscription_run(run, user, changes, previous_schedule = nil)
    if run
      params = {}
      changes.each do |k, change|
        case k
        when 'scheduled_start_time'
          params["Scheduled Start Time"] = [change[0].try(:strftime,'%I:%M%P'), run.scheduled_start_time.strftime('%I:%M%P')] if !compare_time_only(change[0], change[1])
        when 'scheduled_end_time'
          params["Scheduled End Time"] = [change[0].try(:strftime,'%I:%M%P'), run.scheduled_end_time.strftime('%I:%M%P')] if !compare_time_only(change[0], change[1])
        when 'vehicle_id'
          old_vehicle = Vehicle.find_by_id change[0]
          params["Vehicle"] = [old_vehicle.try(:name), run.vehicle.try(:name)] 
        when 'driver_id'
          old_driver = Driver.find_by_id change[0]
          params["Driver"] = [old_driver.try(:user_name), run.driver.try(:user_name)]
        when 'start_date'
          params["Start Date"] = [change[0].try(:strftime, "%B %d, %Y"), run.start_date.try(:strftime, "%B %d, %Y")]
        when 'end_date'
          params["End Date"] = [change[0].try(:strftime, "%B %d, %Y"), run.end_date.try(:strftime, "%B %d, %Y")]
        end
      end

      previous_schedule_desc = previous_schedule.try(:to_s) rescue ""
      current_schedule_desc = run.schedule.try(:to_s) rescue ""
      if previous_schedule_desc != current_schedule_desc
        params["Schedule"] = [previous_schedule_desc, current_schedule_desc]
      end

      run.create_activity :subscription_updated, owner: user, params: params unless params.blank?
    end
  end

  def self.update_run(run, user, changes)
    if run
      params = {}
      changes.each do |k, change|
        case k
        when 'scheduled_start_time'
          params["Scheduled Start Time"] = [change[0].try(:strftime,'%I:%M%P'), run.scheduled_start_time.strftime('%I:%M%P')] if !compare_time_only(change[0], change[1])
        when 'scheduled_end_time'
          params["Scheduled End Time"] = [change[0].try(:strftime,'%I:%M%P'), run.scheduled_end_time.strftime('%I:%M%P')] if !compare_time_only(change[0], change[1])
        when 'vehicle_id'
          old_vehicle = Vehicle.find_by_id change[0]
          params["Vehicle"] = [old_vehicle.try(:name), run.vehicle.try(:name)] 
        when 'driver_id'
          old_driver = Driver.find_by_id change[0]
          params["Driver"] = [old_driver.try(:user_name), run.driver.try(:user_name)]
        end
      end


      run.create_activity :updated, owner: user, params: params unless params.blank?
    end
  end

  def self.complete_run(run, user)
    if run && run.complete? 
      run.create_activity :completed, owner: user
    end
  end

  def self.uncomplete_run(run, user)
    if run && !run.complete? 
      run.create_activity :uncompleted, owner: user, params: {reason: run.uncomplete_reason}
    end
  end

  def self.change_vehicle_initial_mileage(vehicle, user, prev_mileage)
    if vehicle 
      vehicle.create_activity :initial_mileage_changed, owner: user, params: {
        mileage: [prev_mileage, vehicle.initial_mileage], 
        reason: vehicle.initial_mileage_change_reason
      }
    end
  end

  def self.vehicle_active_status_changed(vehicle, user, prev_active_text, prev_reason)
    return if !vehicle

    vehicle.create_activity :active_status_changed, owner: user, params: {
      prev_active_status_text: prev_active_text,
      active_status_text: vehicle.active_status_text,
      prev_reason: prev_reason || '(not provided)',
      reason: vehicle.active_status_changed_reason  || '(not provided)'
    }  
  end

  def self.driver_active_status_changed(driver, user, prev_active_text, prev_reason)
    return if !driver

    driver.create_activity :active_status_changed, owner: user, params: {
      prev_active_status_text: prev_active_text,
      active_status_text: driver.active_status_text,
      prev_reason: prev_reason.blank? ? '(not provided)' : prev_reason,
      reason: driver.active_status_changed_reason.blank? ?  '(not provided)' : driver.active_status_changed_reason
    }  
  end

  def self.customer_active_status_changed(customer, user, prev_active_text, prev_reason)
    return if !customer

    customer.create_activity :active_status_changed, owner: user, params: {
      prev_active_status_text: prev_active_text,
      active_status_text: customer.active_status_text,
      prev_reason: prev_reason.blank? ? '(not provided)' : prev_reason,
      reason: customer.active_status_changed_reason.blank? ?  '(not provided)' : customer.active_status_changed_reason
    }  
  end

  def self.customer_comments_created(customer, user)
    return if !customer

    customer.create_activity :customer_comments_created, owner: user
  end

  def self.customer_comments_updated(customer, user)
    return if !customer

    customer.create_activity :customer_comments_updated, owner: user
  end

  def self.provider_active_status_changed(provider, user)
    return if !provider

    provider.create_activity :active_status_changed, owner: user, params: {
      active: provider.active?,
      reason: provider.inactivated_reason  || '(not provided)'
    }  
  end

  def self.trip_scheduled_to_run(trip, user, from, to)
    return if !trip
    params = {
      from: from,
      to: to
    } 

    trip.create_activity :trip_scheduled, owner: user, params: params
  end

  def self.trips_added_to_run(run, trips, user, day_of_week = nil)
    return if !run || !trips || trips.empty?
    params = {
      count: trips.size
    } 
    if day_of_week
      params[:day_of_week] = day_of_week
    end

    run.create_activity :trip_added, owner: user, params: params
  end

  def self.trips_removed_from_run(run, trips, user, day_of_week = nil)
    return if !run || !trips || trips.empty?

    params = {
      count: trips.size
    } 
    if day_of_week
      params[:day_of_week] = day_of_week
    end

    run.create_activity :trip_removed, owner: user, params: params
  end

  def self.rearrange_trip_itineraries(run, user, day_of_week = nil)
    return if !run

    if day_of_week
      run.create_activity :itinerary_rearranged, owner: user, params: {
        day_of_week: day_of_week
      }
    else
      run.create_activity :itinerary_rearranged, owner: user
    end
  end

  def self.revoke_run_cancellation(run, user, trips_back)
    return if !run
    run.create_activity :run_cancellation_revoked, owner: user, params: { trips_back: trips_back }
  end

  def self.cancel_run(run, user, day_of_week = nil)
    return if !run

    if day_of_week
      run.create_activity :run_cancelled, owner: user, params: {
        day_of_week: day_of_week
      }
    else
      run.create_activity :run_cancelled, owner: user
    end
  end

  private

  def self.compare_time_only(time_1, time_2)
    if time_1 && time_2
      time_1.utc.strftime( "%H%M%S%N" ) == time_2.utc.strftime( "%H%M%S%N" )
    else
      !time_1 && !time_2
    end
  end
end