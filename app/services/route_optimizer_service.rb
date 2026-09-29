# Reorders one demand-response run's stops with the optimizer sidecar
# (optimizer_service/, OR-Tools over OSRM).
#
#   RouteOptimizerService.optimize_run(run)   # => result hash, see below
#
# The optimizer keeps each pickup inside its window (booked time -5/+10 min),
# each drop-off before the appointment time, each rider's time on board under
# the ride limit (max of 1.5x the direct drive and direct + 20 min), two
# minutes of boarding per stop, and the bus inside the run's hours. It returns
# the full stop sequence, pickups and drop-offs interleaved, and that exact
# sequence becomes the run's manifest.
#
# Nothing on the run changes unless every trip fits ("success"). If some trips
# cannot be served under those rules the result is "partial" with
# unassigned_trip_ids, so dispatch can move them to another run, and the run
# is left as it was. A run that has started, or has a finished stop, is not
# touched: rebuilding the manifest deletes and recreates every stop.
#
# Result keys: "solver_status" (success | partial | fail | skipped),
# "applied", "message", plus the optimizer's stops / unassigned_trip_ids /
# total_distance_m / total_drive_seconds.
class RouteOptimizerService
  OPTIMIZER_URL = ENV.fetch("OPTIMIZER_URL", "http://localhost:8765")
  PICKUP_SLACK_BEFORE = 5.minutes.to_i
  PICKUP_SLACK_AFTER  = 10.minutes.to_i

  def self.optimize_run(run)
    new(run).call
  end

  def initialize(run)
    @run = run
  end

  def call
    if (why = not_optimizable)
      return { "solver_status" => "skipped", "applied" => false, "message" => why }
    end
    payload = build_payload
    return { "solver_status" => "skipped", "applied" => false, "message" => "No trips on this run have both addresses geocoded." } if payload[:trips].empty?

    result = post(payload)
    result["applied"] = false
    if result["solver_status"] == "success"
      apply_result(result)
      result["applied"] = true
    end
    result["message"] = summary(result, payload[:trips].size)
    result
  end

  private

  def not_optimizable
    return "Only demand-response runs can be optimized." if @run.fixed_route?
    return "This run has started, so its stops are left as they are." if @run.actual_start_time.present?
    return "Some stops on this run are already finished, so its stops are left as they are." if @run.itineraries.finished.exists?
    return "The run needs at least two trips to optimize." if @run.trips.count < 2
    nil
  end

  def post(payload)
    uri = URI("#{OPTIMIZER_URL}/optimize/run")
    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = 45
    request = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
    request.body = payload.to_json
    response = http.request(request)
    raise "Optimizer HTTP #{response.code}: #{response.body}" unless response.code == "200"
    JSON.parse(response.body)
  end

  def build_payload
    depot_address = @run.from_garage_address || @run.vehicle&.garage_address

    {
      run_id: @run.id,
      vehicle_capacity_seats:     @run.vehicle&.seating_capacity || 8,
      vehicle_capacity_tie_downs: @run.vehicle&.mobility_device_accommodations || 2,
      depot_lat: depot_address&.latitude&.to_f,
      depot_lng: depot_address&.longitude&.to_f,
      earliest_start: seconds_from_midnight(@run.scheduled_start_time),
      latest_end:     seconds_from_midnight(@run.scheduled_end_time),
      trips: @run.trips.includes(:pickup_address, :dropoff_address, :ridership_mobilities)
                 .map { |t| serialize_trip(t) }
                 .compact
    }
  end

  def serialize_trip(trip)
    return nil unless trip.pickup_address&.latitude && trip.dropoff_address&.latitude
    return nil unless trip.pickup_time

    pickup_seconds = seconds_from_midnight(trip.pickup_time)

    {
      trip_id:         trip.id,
      pickup_lat:      trip.pickup_address.latitude.to_f,
      pickup_lng:      trip.pickup_address.longitude.to_f,
      dropoff_lat:     trip.dropoff_address.latitude.to_f,
      dropoff_lng:     trip.dropoff_address.longitude.to_f,
      earliest_pickup: [pickup_seconds - PICKUP_SLACK_BEFORE, 0].max,
      latest_pickup:   [pickup_seconds + PICKUP_SLACK_AFTER, 86399].min,
      latest_dropoff:  trip.appointment_time && seconds_from_midnight(trip.appointment_time),
      seats:           trip_seat_count(trip),
      tie_downs:       trip_tiedown_count(trip)
    }
  end

  # The optimizer's stop sequence becomes the manifest; each trip's estimated
  # pickup time is the optimizer's arrival at its pickup.
  def apply_result(result)
    ActiveRecord::Base.transaction do
      midnight = @run.date.in_time_zone(timezone).beginning_of_day

      result["stops"].select { |s| s["kind"] == "pickup" }.each do |stop|
        eta_time = midnight + stop["eta"].seconds
        trip = Trip.find(stop["trip_id"])
        previous_eta = trip.estimated_pickup_time
        trip.update_columns(estimated_pickup_time: eta_time)

        # Notify customer if ETA shifted >5 minutes
        if previous_eta && (eta_time - previous_eta).abs > 5.minutes && SmsNotificationService.sms_enabled?
          SmsNotificationJob.perform_later(
            trip.customer_id,
            :schedule_change,
            new_time: eta_time.in_time_zone(timezone).strftime("%I:%M %p"),
            phone: @run.provider.phone_number
          )
        end
      end

      manifest_order = ["run_begin"]
      result["stops"].each do |stop|
        manifest_order << "trip_#{stop['trip_id']}_leg_#{stop['kind'] == 'pickup' ? 1 : 2}"
      end
      manifest_order << "run_end"

      @run.manifest_order = manifest_order
      @run.manifest_changed = true
      @run.save(validate: false)
      @run.reset_itineraries
    end
  end

  def summary(result, trip_count)
    case result["solver_status"]
    when "success"
      miles = (result["total_distance_m"].to_f / 1609.34).round(1)
      minutes = (result["total_drive_seconds"].to_i / 60.0).round
      "Route optimized: #{trip_count} trips, #{result['stops'].size} stops, about #{miles} mi and #{minutes} min of driving."
    when "partial"
      names = Trip.where(id: result["unassigned_trip_ids"]).includes(:customer)
                  .map { |t| "#{t.customer&.name} (#{t.pickup_time&.in_time_zone(timezone)&.strftime('%-l:%M %p')})" }
      "Not changed: #{names.to_sentence} can't be served on this run inside the pickup windows, appointment times, " \
        "ride-time limit and run hours. Move #{names.size == 1 ? 'that trip' : 'those trips'} to another run and optimize again."
    else
      "The optimizer found no workable route for this run; nothing was changed."
    end
  end

  def seconds_from_midnight(time)
    return nil unless time
    local = time.in_time_zone(timezone)
    (local - local.beginning_of_day).to_i
  end

  def trip_seat_count(trip)
    # Use customer_space_count if set, otherwise default to 1
    count = trip.customer_space_count.to_i
    count > 0 ? count : 1
  end

  def trip_tiedown_count(trip)
    # Check ridership mobilities for wheelchair/mobility device needs
    # Mobility devices that require tie-downs have capacity in the
    # "Wheelchair" or similar capacity type
    return 0 unless trip.ridership_mobilities.has_capacity.any?

    wheelchair_capacity_type_ids = CapacityType.where("lower(name) LIKE ?", "%wheelchair%")
                                               .or(CapacityType.where("lower(name) LIKE ?", "%tie%down%"))
                                               .pluck(:id)
    return 0 if wheelchair_capacity_type_ids.empty?

    total = 0
    trip.ridership_mobilities.has_capacity.each do |rm|
      mc = MobilityCapacity.where(host_id: rm.mobility_id, capacity_type_id: wheelchair_capacity_type_ids)
                           .where("capacity > 0")
      total += rm.capacity * mc.sum(:capacity) if mc.any?
    end
    total
  end

  def timezone
    "Central Time (US & Canada)"
  end
end
