#-------------------------------------------------------------------------------
# RunEtaEstimator
#
# Live, GPS-driven ETA for an in-progress run. Takes the vehicle's most recent
# position (from gps_locations, fed by AvlPollerWorker) and routes through the
# remaining manifest stops via OSRM, accumulating travel time + per-stop dwell.
# Writes each upcoming pickup's ETA to trips.estimated_pickup_time (the rider-
# facing field read by the client portal + SMS ETA jobs) and the per-leg
# public_itineraries.eta.
#
# This is the "en-route" layer of the ETA: it refines the scheduled/optimized
# time with where the van actually is, and is recomputed every AVL poll.
#-------------------------------------------------------------------------------
class RunEtaEstimator
  OSRM_URL         = ENV['OSRM_URL'].presence || 'http://osrm:5000'
  GPS_MAX_AGE      = 10.minutes   # ignore stale positions
  DEFAULT_DWELL_S  = 60           # fallback per-stop dwell when load/unload unset

  def self.update_for(run_id)
    run = Run.find_by_id(run_id)
    new(run).update! if run
  end

  def initialize(run)
    @run = run
  end

  # Returns the number of pickup ETAs written (nil if it couldn't run).
  def update!
    gps = latest_gps
    return nil unless gps

    legs = remaining_legs
    return 0 if legs.empty?

    durations = osrm_leg_durations(gps, legs)
    return nil unless durations && durations.size == legs.size

    written = 0
    cursor = Time.current
    legs.each_with_index do |leg, i|
      cursor += durations[i].to_i            # drive time to this stop
      leg.public_itinerary&.update_columns(eta: cursor)
      if leg.is_pickup? && leg.trip
        leg.trip.update_columns(estimated_pickup_time: cursor)
        written += 1
      end
      cursor += dwell_seconds(leg)           # time spent at this stop
    end
    written
  end

  private

  def latest_gps
    g = GpsLocation.where(run_id: @run.id).order(log_time: :desc).first
    return nil unless g&.log_time && g.latitude && g.longitude
    return nil if g.log_time < GPS_MAX_AGE.ago
    g
  end

  # Remaining, not-yet-completed legs in manifest order (default scope excludes
  # soft-deleted legs). Only those with a geocoded address are routable.
  def remaining_legs
    Itinerary.joins(:public_itinerary)
             .where(public_itineraries: { run_id: @run.id })
             .where(status_code: [nil, Itinerary::STATUS_PENDING, Itinerary::STATUS_IN_PROGRESS])
             .order('public_itineraries.sequence')
             .to_a
             .select { |l| l.address&.latitude.present? && l.address&.longitude.present? }
  end

  def dwell_seconds(leg)
    trip = leg.trip
    mins = leg.is_pickup? ? trip&.passenger_load_min : trip&.passenger_unload_min
    (mins.presence ? mins.to_i * 60 : DEFAULT_DWELL_S)
  end

  # One OSRM /route call: waypoint 0 is the live GPS position, then each leg in
  # order. routes[0].legs[i].duration is the drive time to legs[i].
  def osrm_leg_durations(gps, legs)
    points = [[gps.longitude, gps.latitude]] +
             legs.map { |l| [l.address.longitude, l.address.latitude] }
    coords = points.map { |lon, lat| "#{lon},#{lat}" }.join(';')
    url = "#{OSRM_URL}/route/v1/driving/#{coords}?overview=false&steps=false"

    resp = Net::HTTP.get_response(URI(url))
    return nil unless resp.code.to_i == 200
    data = JSON.parse(resp.body)
    return nil unless data['code'] == 'Ok'
    data['routes'].first['legs'].map { |leg| leg['duration'] }
  rescue => e
    Rails.logger.warn "RunEtaEstimator OSRM failure for run #{@run.id}: #{e.message}"
    nil
  end
end
