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
    payload = build_payload
    return { "error" => "No trips on run" } if payload[:trips].empty?

    uri = URI("#{OPTIMIZER_URL}/optimize/run")
    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = 30

    request = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
    request.body = payload.to_json

    response = http.request(request)
    raise "Optimizer HTTP #{response.code}: #{response.body}" unless response.code == "200"

    result = JSON.parse(response.body)
    apply_result(result) if result["solver_status"] == "success"
    result
  end

  private

  def build_payload
    depot_address = @run.from_garage_address || @run.vehicle&.garage_address

    {
      run_id: @run.id,
      vehicle_capacity_seats:     @run.vehicle&.seating_capacity || 8,
      vehicle_capacity_tie_downs: @run.vehicle&.mobility_device_accommodations || 2,
      depot_lat: depot_address&.latitude&.to_f,
      depot_lng: depot_address&.longitude&.to_f,
      trips: @run.trips.includes(:pickup_address, :dropoff_address, :ridership_mobilities)
                 .map { |t| serialize_trip(t) }
                 .compact
    }
  end

  def serialize_trip(trip)
    return nil unless trip.pickup_address&.latitude && trip.dropoff_address&.latitude
    return nil unless trip.pickup_time

    pickup_local = trip.pickup_time.in_time_zone(timezone)
    midnight = pickup_local.beginning_of_day
    pickup_seconds = (pickup_local - midnight).to_i

    {
      trip_id:         trip.id,
      pickup_lat:      trip.pickup_address.latitude.to_f,
      pickup_lng:      trip.pickup_address.longitude.to_f,
      dropoff_lat:     trip.dropoff_address.latitude.to_f,
      dropoff_lng:     trip.dropoff_address.longitude.to_f,
      earliest_pickup: [pickup_seconds - PICKUP_SLACK_BEFORE, 0].max,
      latest_pickup:   [pickup_seconds + PICKUP_SLACK_AFTER, 86399].min,
      seats:           trip_seat_count(trip),
      tie_downs:       trip_tiedown_count(trip)
    }
  end

  def apply_result(result)
    ActiveRecord::Base.transaction do
      midnight = @run.date.in_time_zone(timezone).beginning_of_day

      result["ordered_trip_ids"].each_with_index do |trip_id, position|
        eta_seconds = result["etas"][position]
        eta_time = midnight + eta_seconds.seconds

        trip = Trip.find(trip_id)
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

      # Build manifest_order: pickup (leg_1) then dropoff (leg_2) per trip
      manifest_order = ["run_begin"]
      result["ordered_trip_ids"].each do |trip_id|
        manifest_order << "trip_#{trip_id}_leg_1"
        manifest_order << "trip_#{trip_id}_leg_2"
      end
      manifest_order << "run_end"

      @run.manifest_order = manifest_order
      @run.manifest_changed = true
      @run.save(validate: false)
      @run.reset_itineraries
    end
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
