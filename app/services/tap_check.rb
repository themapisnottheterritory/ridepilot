# Tap check (Philz 2026-10-04): stops on the driver tablet are meant to be tapped
# as they happen. Launch week showed many tapped in bursts afterwards: three or
# more stops at different places within a couple of minutes, which no van can
# drive. Those times and places are wrong for dispatch, for the rider's record and
# for learning where drivers stop (DriverStops ignores them). Kristie needs to
# know, run by run, so she can follow up: this is that list. It reports what
# happened on each run; it doesn't rank or score anyone.
#
# No false positives (Philz): only facts a wrong map pin, a dead zone, a re-sync
# or an older app can't explain are reported.
#   burst      3+ stops tapped within 90 s of each other, at 2+ places whose pins
#              are over 200 m apart (riders at one complex or clinic don't count),
#              and every one of those taps proven made online: the app's own tap
#              time (1.0.30+, clocks synced) and its arrival within 2 minutes
#              (StopTap#online?). Taps saved in a dead zone keep the time they
#              were made, so a re-sync never makes a burst; a tablet clock that is
#              off makes taps look offline, so it can only hide a burst.
#   at depot   a pickup/drop-off tapped online while the tablet itself (1.0.31+,
#              fix good to 50 m) was at the depot, for a stop more than 300 m away
#   not tapped a stop still open after the run's day, only when that driver's
#              tablet was on 1.0.30+ that day and has reported since with no taps
#              waiting (cancelled and no-show trips excluded)
class TapCheck
  BURST_GAP   = 90.seconds
  BURST_MIN   = 3
  PLACE_APART = 200
  DEPOT_M     = 200

  Run = Struct.new(:run, :driver, :van, :stops, :tapped, :bursts, :burst_stops, :at_depot, :not_tapped, :unchecked, keyword_init: true) do
    def issues? = burst_stops.positive? || at_depot.positive? || not_tapped.positive?
  end

  # -> [TapCheck::Run] for every demand-response run that day
  def self.day(date, provider_ids: [1, 107, 143])   # GCRPC, Goliad, Lavaca
    runs = ::Run.where(date: date, provider_id: provider_ids).where(fixed_route_id: nil)
                .includes(:driver, :vehicle).reject { |r| r.name.to_s =~ /fake|test/i }
    depots = Address.where(type: 'GarageAddress').where.not(the_geom: nil).map { |a| [a.latitude, a.longitude] }
    runs.map do |r|
      stops = r.itineraries.where(leg_flag: [1, 2]).includes(:address, trip: :trip_result).to_a
                .reject { |i| %w[CANC TD UNMET LTCANC SDCANC].include?(i.trip&.trip_result&.code) }
      tapped = stops.select(&:finish_time)
      taps = StopTap.where(itinerary_id: tapped.map(&:id), action: %w[pickup dropoff noshow]).group_by(&:itinerary_id)
      online = ->(i) { (taps[i.id] || []).any?(&:online?) }
      groups = bursts(tapped)
      proven = groups.select { |g| g.all?(&online) }
      user = r.driver&.user
      Run.new(run: r, driver: user&.display_name.presence || "No driver", van: r.vehicle&.name,
              stops: stops.size, tapped: tapped.size, bursts: proven, burst_stops: proven.sum(&:size),
              at_depot: tapped.count { |i| online.(i) && at_depot?(i, taps[i.id], depots) },
              not_tapped: not_tapped(stops, user, date),
              unchecked: groups.size - proven.size)
    end.reject { |x| x.stops.zero? }.sort_by { |x| [x.issues? ? 0 : 1, x.run.name.to_s] }
  end

  # Open stops count only when the driver's tablet could have sent them: on 1.0.30+
  # that day (taps kept offline) and reporting since the day ended with none waiting.
  def self.not_tapped(stops, user, date)
    return 0 if date >= Date.current || user.nil?
    open = stops.count { |i| i.finish_time.nil? && i.trip&.trip_result&.code != 'NS' }
    return 0 if open.zero?
    tablet = Tablet.where(username: user.username).order(last_seen_at: :desc).first
    return 0 unless tablet && tablet.last_seen_at && tablet.last_seen_at > (date + 1).in_time_zone.beginning_of_day
    versions = TabletPing.where(tablet_id: tablet.id, at: date.in_time_zone.all_day).distinct.pluck(:app_version)
    return 0 unless versions.any? && versions.all? { |v| keeps_taps_offline?(v) }
    return 0 unless ((tablet.info || {})["by_app"] || {}).dig("dr", "pending_taps").to_i.zero?
    open
  end

  # 1.0.30 is the first release that keeps taps made with no signal.
  def self.keeps_taps_offline?(version)
    Gem::Version.new(version.to_s[/\A\d+(\.\d+)*/] || "0") >= Gem::Version.new("1.0.30")
  end

  # Taps in a burst: consecutive taps no more than 90 s apart, 3 or more of them,
  # at 2 or more places. -> [[itinerary, ...], ...]
  def self.bursts(tapped)
    groups = tapped.sort_by(&:finish_time).slice_when { |a, b| b.finish_time - a.finish_time > BURST_GAP }
    groups.select { |g| g.size >= BURST_MIN && places_apart?(g) }
  end

  def self.places_apart?(group)
    pts = group.map { |i| i.address&.the_geom && [i.address.latitude, i.address.longitude] }.compact.uniq
    pts.combination(2).any? { |a, b| DriverStops.meters(*a, *b) > PLACE_APART }
  end

  # The burst's stop ids, for DriverStops to leave out.
  def self.burst_ids(tapped) = bursts(tapped).flatten.map(&:id)

  # Tapped at the depot: the tablet's own position at an online tap (1.0.31+) put it
  # at a depot, for a stop more than 300 m from one. Only the tablet's fix counts:
  # the van's GPS halt matched to a stop isn't where the van was at the tap.
  def self.at_depot?(itin, taps, depots)
    return false if depots.empty? || itin.address&.the_geom.nil?
    return false if depots.any? { |d| DriverStops.meters(*d, itin.address.latitude, itin.address.longitude) < 300 }
    pos = (taps || []).select { |t| t.online? && t.latitude && t.accuracy_m.to_i.between?(1, 50) }.last
    return false unless pos
    depots.any? { |d| DriverStops.meters(*d, pos.latitude, pos.longitude) < DEPOT_M }
  end
end
