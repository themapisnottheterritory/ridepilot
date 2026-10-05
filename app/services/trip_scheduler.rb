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
    # Each refusal names the run, its day and (for times) its hours, so dispatch can
    # see it checked e.g. tomorrow's RVIC1, which nobody has staffed yet, and not
    # today's (Jacqueline Gonzalez's 7:00 trip, 2026-10-05). The trouble board keeps
    # only the plain message, so its counts still group by kind of refusal.
    reasons = []
    reasons << [:not_fit_in_run_schedule, time_detail] if !validate_time_availability

    if !@run.vehicle
      reasons << [:no_vehicle_assigned, run_label]
    elsif !validate_vehicle_availability 
      reasons << [:vehicle_unavailable, "#{run_label}: #{@run.vehicle.name}"]
    end

    if !@run.driver
      reasons << [:no_driver_assigned, run_label]
    elsif !validate_driver_availability 
      reasons << [:driver_unavailable, "#{run_label}: #{@run.driver.name}"]
    end

    reasons.each { |key, detail| errors << "#{TranslationEngine.translate_text(key)} (#{detail})" }

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
    TroubleWatch.messages(reasons.map { |key, _| TranslationEngine.translate_text(key) })   # trouble board: plain reasons

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

  # "RVIC1, Tue Oct 6"
  def run_label
    [@run.name, @run.date&.strftime("%a %b %-d")].compact.join(", ")
  end

  # "RVIC1, Tue Oct 6, runs 8:00 AM - 5:00 PM; pickup is 7:00 AM"
  def time_detail
    hours = [@run.scheduled_start_time, @run.scheduled_end_time].map { |t| clock(t) }.join(" - ")
    detail = "#{run_label}, runs #{hours}; pickup is #{clock(@trip.pickup_time)}"
    detail += ", appointment #{clock(@trip.appointment_time)}" if @trip.appointment_time
    detail
  end

  def clock(time)
    time&.in_time_zone&.strftime("%-l:%M %p")
  end

  def time_portion(time)
    (time - time.beginning_of_day) if time
  end

end