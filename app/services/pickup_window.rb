# A trip's pick-up window and the no-show rules that come with it, from the
# agency's settings (Admin > General > "Pick-up window and no-shows"). These
# are the ADA rules for complementary paratransit, as FTA explains them in
# Circular C 4710.1 (ADA Guidance, 2015); GCRPC applies them to all
# demand-response trips.
#
#   window = PickupWindow.for(trip)
#   window.opens / window.closes      # 11:45 - 12:15 with a 0/+30 window
#   window.no_show_from               # 11:50: the window opens, then the wait
#   window.earliest_boarding          # 11:45, or 11:30 for a rider who agreed
#                                     # to an early pick-up (15 min allowance)
#   window.no_show_refusal(at: Time.current, arrived_at: itin.arrival_time)
#   # => nil, or why a no-show can't be recorded, citing the rule
#
# Why (Ron and Robert Gardner, DeWitt3, 2026-10-06): the tablet estimated a
# drop-off before its pick-up because it assumed riders board the moment the
# bus arrives, however early. And over the 30 days before, 42 of Victoria's 103
# no-shows were recorded before the booked time, and 21 after the bus came
# later than the window -- which FTA counts as missed trips, not no-shows.
class PickupWindow
  RULES = {
    window: "FTA Circular C 4710.1 §8.4.5: a pick-up window may be at most 30 minutes in all, either after the booked time (0/+30) or around it (-15/+15).",
    early: "FTA Circular C 4710.1 §8.5.3: a rider doesn't have to board before the pick-up window opens, and must not be pressured to.",
    wait: "FTA Circular C 4710.1 §8.5.3: the driver's wait starts when the pick-up window opens, not when the bus arrives.",
    missed: "FTA Circular C 4710.1 §8.5.4: a bus that arrives after the window, leaves before it opens, or leaves without waiting the full time is a missed trip (the agency's), not a no-show (the rider's).",
    suspension: "49 CFR 37.125(h), FTA Circular C 4710.1 §9.12: no-shows can lead to a suspension of service, so only true no-shows may be recorded."
  }.freeze

  attr_reader :trip, :booked, :opens, :closes, :no_show_from, :earliest_boarding, :wait_minutes

  # nil for a trip with no booked pick-up time, a will-call, or a cab trip
  def self.for(trip)
    return nil unless trip && trip.pickup_time && trip.provider && !trip.try(:will_call) && !trip.try(:cab)
    new(trip)
  end

  def initialize(trip)
    p = trip.provider
    @trip = trip
    @booked = trip.pickup_time
    @opens = booked - p.pickup_window_early_min.to_i.minutes
    @closes = booked + p.pickup_window_late_min.to_i.minutes
    @wait_minutes = p.no_show_wait_min.to_i
    @no_show_from = opens + wait_minutes.minutes
    @earliest_boarding = trip.early_pickup_allowed ? opens - p.early_boarding_min.to_i.minutes : opens
  end

  # Why a no-show can't be recorded now, or nil when it can. `at`: when the
  # driver tapped No Show (or now, for dispatch); `arrived_at`: when the bus
  # reached the pick-up, if the driver tapped Arrive.
  def no_show_refusal(at:, arrived_at: nil)
    if arrived_at && arrived_at > closes
      "The bus reached #{rider} at #{clock(arrived_at)}, after the pick-up window closed at #{clock(closes)}. " \
        "That is a missed trip, not a no-show: record it as Missed Trip. (#{RULES[:missed]})"
    elsif at < no_show_from
      "Too early for a no-show. #{rider.sub(/\A./, &:upcase)}'s pick-up window opens at #{clock(opens)}, and the driver waits " \
        "#{wait_minutes} minutes from then, so a no-show can be recorded from #{clock(no_show_from)}. " \
        "(#{RULES[:early]} #{RULES[:wait]})"
    end
  end

  def to_h
    { opens: opens.iso8601, closes: closes.iso8601, no_show_from: no_show_from.iso8601, wait_minutes: wait_minutes }
  end

  private

  def rider
    trip.customer&.name.presence || "the rider"
  end

  def clock(t)
    t.in_time_zone.strftime('%-l:%M %p')
  end
end
