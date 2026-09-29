class TripScheduler
  attr_reader :trip, :run, :errors

  def initialize(trip_id, run_id)
    @trip = Trip.find_by_id(trip_id)
    @run = get_run(run_id.to_i)
    @errors = []
  end

  def execute
    return if !@trip || !@run 

    return if @trip.adjusted_run_id == @run.id

    case @run.id
    when Run::UNSCHEDULED_RUN_ID
      unschedule
    when Run::STANDBY_RUN_ID 
      schedule_to_standby
    when Run::CAB_RUN_ID 
      schedule_to_cab
    else
      schedule_to_run
    end
  end

  private

  def get_run(run_id)
    case run_id
    when Run::CAB_RUN_ID 
      Run.fake_cab_run
    when Run::UNSCHEDULED_RUN_ID
      Run.fake_unscheduled_run
    else
      Run.find_by_id(run_id)
    end
  end

  def unschedule
    remove_trip_manifest(@trip.run, @trip.id)
    @trip.cab = false 
    @trip.run = nil 
    @trip.is_stand_by = false
    @trip.save(validate: false)
  end

  def schedule_to_standby
    remove_trip_manifest(@trip.run, @trip.id)
    @trip.cab = false 
    @trip.run = nil 
    @trip.is_stand_by = true
    @trip.save(validate: false)
  end

  def schedule_to_cab
    remove_trip_manifest(@trip.run, @trip.id)
    @trip.cab = true 
    @trip.run = nil 
    @trip.is_stand_by = false
    @trip.save(validate: false)
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
      prev_run = @trip.run
      @trip.cab = false
      @trip.is_stand_by = false
      @trip.run = @run
      if @trip.save
        remove_trip_manifest(prev_run, @trip.id)
        @run.add_trip_manifest!(@trip.id)
      else  
        @errors = @trip.errors.full_messages 
      end
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

  def response_as_json(is_success, error_text = '')
    {
      success: is_success,
      message: error_text || '',
      trip_event_json: is_success ? @trip.as_run_event_json : nil
    }
  end

  def remove_trip_manifest(run, trip_id)
    if run 
      run.delete_trip_manifest!(trip_id)
    end
  end

  private

  def time_portion(time)
    (time - time.beginning_of_day) if time
  end

end