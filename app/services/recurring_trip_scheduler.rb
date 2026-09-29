class RecurringTripScheduler
  attr_reader :trip, :run, :wday, :errors

  def initialize(trip_id, run_id, wday)
    @trip = RepeatingTrip.find_by_id(trip_id)
    @run = RepeatingRun.find_by_id(run_id) if run_id
    @wday = wday
    @errors = []
  end

  def execute
    return if !@trip

    if @run 
      schedule_to_run
    else
      unschedule
    end
  end

  private

  def unschedule
    prev_assignment = @trip.weekday_assignments.for_wday(@wday)
    if prev_assignment.any?
      remove_trip_manifest(prev_assignment.first.repeating_run, @trip.id)
      prev_assignment.delete_all
    end
  end

  def schedule_to_run
    if !validate_time_availability
      errors << TranslationEngine.translate_text(:not_fit_in_run_schedule)
    end

    if !@run.vehicle
      errors << TranslationEngine.translate_text(:no_vehicle_assigned)
    elsif !validate_vehicle_availability 
      errors << TranslationEngine.translate_text(:vehicle_unavailable)
    end

    if !@run.driver
      errors << TranslationEngine.translate_text(:no_driver_assigned)
    elsif !validate_driver_availability 
      errors << TranslationEngine.translate_text(:driver_unavailable)
    end

    if errors.empty?
      unschedule
      @run.add_trip_manifest!(@trip.id, @wday)
    end
    TroubleWatch.messages(errors)   # the reasons dispatch was shown (trouble board)
  end

  # run avaiability validations

  # run can hold a trip
  def validate_time_availability
    run_start_time = @run.scheduled_start_time
    run_end_time = @run.scheduled_end_time

    if run_start_time && run_end_time
      (time_portion(@trip.pickup_time) >= time_portion(run_start_time)) && 
      (time_portion(@trip.pickup_time) < time_portion(run_end_time)) && 
      (@trip.appointment_time.nil? || time_portion(@trip.appointment_time) <= time_portion(run_end_time))
    else
      true
    end
  end

  def validate_vehicle_availability
    @run.vehicle && @run.vehicle.active
  end

  def validate_driver_availability
    @run.driver && @run.driver.active
  end

  private

  def time_portion(time)
    (time - time.beginning_of_day) if time
  end

  def remove_trip_manifest(run, trip_id)
    if run 
      run.weekday_assignments.for_wday(@wday).where(repeating_trip_id: trip_id).delete_all
      run.delete_trip_manifest!(trip_id, @wday)
    end
  end

end