# Splits a demand-response run in two at a time of day. The run keeps its
# driver, bus and the trips picked up before that time, and now ends then; a
# new run takes the rest of its hours and trips, with its own driver and bus.
#
# For split shifts (2026-10-09: Allen Mehrtens on UDR in the morning and
# DeWitt in the afternoon). A driver can't be on two runs whose hours
# overlap, so each run is cut at the handover and the halves staffed apart.
class RunSplitter
  attr_reader :run, :new_run, :errors, :moved_trips

  def initialize(run, at:, name:, driver_id: nil, vehicle_id: nil, user: nil)
    @run = run
    @at = parse_time(at)
    @name = name.to_s.strip
    @driver_id = driver_id.presence
    @vehicle_id = vehicle_id.presence || run.vehicle_id
    @user = user
    @errors = []
    @moved_trips = []
  end

  def at
    @at
  end

  # Trips the new run would take: picked up at or after the split time.
  def moving_trips
    return Trip.none unless @at
    run.trips.where("trips.pickup_time >= ?", @at)
  end

  # Picked up before the split time but dropped off after it: whose would they be?
  def straddling_trips
    return Trip.none unless @at
    run.trips.where("trips.pickup_time < ? AND trips.appointment_time > ?", @at, @at)
  end

  def call
    check
    return false if errors.any?

    published = run.public_itineraries.exists?
    old_end = run.scheduled_end_time
    order = Array(run.manifest_order)

    Run.transaction do
      # The run itself: end it at the split. Shorter hours can't clash with
      # anything, so don't let an unrelated old validation block it.
      run.scheduled_end_time = @at
      run.save!(validate: false)

      @new_run = Run.new(provider_id: run.provider_id, date: run.date, name: @name,
                         service_mode: run.service_mode, paid: run.paid,
                         scheduled_start_time: @at, scheduled_end_time: old_end,
                         driver_id: @driver_id, vehicle_id: @vehicle_id)
      unless @new_run.is_all_valid?(run.provider_id)
        @errors = clash_messages.presence || @new_run.errors.full_messages
        raise ActiveRecord::Rollback
      end
      @new_run.save!
      garage = @new_run.vehicle.try(:garage_address)
      if @vehicle_id.to_i == run.vehicle_id && run.to_garage_address
        # the same bus changing drivers: it ends where the run did
        @new_run.update_columns(from_garage_address_id: run.to_garage_address_id, to_garage_address_id: run.to_garage_address_id)
      elsif garage
        @new_run.from_garage_address = garage.for_run
        @new_run.to_garage_address = garage.for_run
        @new_run.save!(validate: false)
      end
      @new_run.refresh_garage_stops!

      @moved_trips = moving_trips.to_a
      @moved_trips.each do |trip|
        trip.run = @new_run
        trip.save(validate: false)
        run.delete_trip_manifest!(trip.id)
        @new_run.add_trip_manifest!(trip.id)
      end

      # Keep the stops in the order dispatch had them.
      moved_keys = @moved_trips.map(&:id)
      kept = order.select { |key| key =~ /\Atrip_(\d+)_leg_\d\z/ && moved_keys.include?($1.to_i) }
      if kept.any?
        @new_run.update_columns(manifest_order: kept, manifest_changed: true)
        @new_run.itineraries.clear_times!
      end
      run.update_columns(manifest_changed: true)

      if published
        notify = run.date == Date.current
        [run.reload, @new_run.reload].select(&:manifest_publishable?).each do |r|
          RunStatsCalculator.new(r.id).process_eta
          r.reload.publish_manifest!(notify)
        end
      end

      if @user
        TrackerActionLog.update_run(run, @user, { "scheduled_end_time" => [old_end, @at] })
        TrackerActionLog.create_run(@new_run, @user)
        TrackerActionLog.trips_removed_from_run(run, @moved_trips, @user) if @moved_trips.any?
        TrackerActionLog.trips_added_to_run(@new_run, @moved_trips, @user) if @moved_trips.any?
      end
    end

    ok = errors.empty? && @new_run&.persisted?
    run.reload unless ok
    ok
  end

  private

  def check
    errors << "Only demand-response runs can be split." unless run.demand_response?
    errors << "This run is complete." if run.complete?
    errors << "This run is cancelled." if run.cancelled?
    errors << "This run is in the past." if run.date && run.date < Date.current
    errors << "Give the new run a name." if @name.blank?
    errors << "Pick a bus for the new run." if @vehicle_id.blank?
    unless @at
      errors << "Enter the time to split at."
      return
    end
    if run.scheduled_start_time && run.scheduled_end_time &&
       !(@at.seconds_since_midnight > run.scheduled_start_time.seconds_since_midnight &&
         @at.seconds_since_midnight < run.scheduled_end_time.seconds_since_midnight)
      errors << "Split between the run's start (#{fmt(run.scheduled_start_time)}) and end (#{fmt(run.scheduled_end_time)})."
    end
    straddling_trips.each do |t|
      errors << "#{t.customer.try(:name)} is picked up at #{fmt(t.pickup_time)} and dropped off at #{fmt(t.appointment_time)}: split before the pickup or after the drop-off."
    end
    started = Itinerary.where(trip_id: moving_trips.select(:id)).where.not(finish_time: nil).pluck(:trip_id).uniq
    Trip.where(id: started).each do |t|
      errors << "#{t.customer.try(:name)} (#{fmt(t.pickup_time)}) has already been picked up; split after that trip."
    end
  end

  # "Allen Mehrtens is on DeWitt1 PM (12:30 PM - 4:00 PM) then." rather than
  # "Driver has been assigned to another overlapping run".
  def clash_messages
    others = Run.other_overlapped_runs(@new_run).not_cancelled
    msgs = []
    if @new_run.errors[:driver_id].any? && (clash = others.find_by(driver_id: @new_run.driver_id))
      msgs << "#{@new_run.driver.name} is on #{clash.name} (#{fmt(clash.scheduled_start_time)} - #{fmt(clash.scheduled_end_time)}) then."
    end
    if @new_run.errors[:vehicle_id].any? && (clash = others.find_by(vehicle_id: @new_run.vehicle_id))
      msgs << "Bus #{@new_run.vehicle.name} is on #{clash.name} (#{fmt(clash.scheduled_start_time)} - #{fmt(clash.scheduled_end_time)}) then."
    end
    msgs.any? ? msgs + (@new_run.errors.full_messages.reject { |m| m =~ /overlapping/ }) : []
  end

  def parse_time(value)
    return nil if value.blank? || run.date.nil?
    hour, min = value.to_s.split(":").map(&:to_i)
    return nil unless hour && min && hour.between?(0, 23) && min.between?(0, 59)
    Time.zone.local(run.date.year, run.date.month, run.date.day, hour, min)
  end

  def fmt(time)
    time&.strftime("%-l:%M %p")
  end
end
