# The fare the office quotes a cash rider, for the trip form, the trip page
# and the dispatch trips pane.
#
#   TripFareQuote.new(trip).call   # => FareSchedule::Quote or nil
#
# For a list, pass one schedule for the provider and skip the distance
# lookup: TripFareQuote.new(trip, schedule: s, compute_distance: false).
#
# A funding source marked no_fare (the funder pays the whole ride) quotes no
# fare. Then an amount already typed on the trip wins. Otherwise the provider's fare
# tables price it (FareSchedule#quote). The trip's drive distance is filled
# by a background job after save, so an unsaved trip, or one saved seconds
# ago, gets its distance worked out here (not saved).
class TripFareQuote
  def initialize(trip, compute_distance: true, schedule: nil)
    @trip = trip
    @compute_distance = compute_distance
    @schedule = schedule
  end

  def call
    return nil unless @trip&.provider
    if (paid = @trip.funding_source)&.no_fare?
      return FareSchedule::Quote.new(amount: 0.to_d, rider: 0.to_d, guests: 0, basis: paid.no_fare_text, no_fare: true)
    end
    if @trip.fare_amount.to_f > 0
      amount = @trip.fare_amount.to_d.round(2)
      return FareSchedule::Quote.new(amount: amount, rider: amount, guests: 0, basis: "set on the trip")
    end
    ensure_distance! if @compute_distance
    (@schedule || FareSchedule.new(@trip.provider)).quote(@trip)
  rescue StandardError => e
    Rails.logger.warn("TripFareQuote trip=#{@trip&.id}: #{e.class}: #{e.message}")
    nil
  end

  private

  def ensure_distance!
    return if @trip.drive_distance.to_f > 0
    from, to = @trip.pickup_address, @trip.dropoff_address
    return unless from&.latitude && from&.longitude && to&.latitude && to&.longitude
    miles = TripDistanceDurationProxy.new(ENV['TRIP_PLANNER_TYPE'], {
      from_lat: from.latitude, from_lon: from.longitude, to_lat: to.latitude, to_lon: to.longitude,
      trip_datetime: @trip.pickup_time
    }).get_drive_distance
    @trip.drive_distance = miles if miles.to_f > 0
  end
end
