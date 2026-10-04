# Where drivers stop (Philz 2026-10-03). For every finished pickup and drop-off,
# where the van actually sat still, from the bus GPS: the Pepwave AVL log on .40
# (avllog, about one position a second per bus). Drivers tap Arrive and Pick Up
# together, often a few seconds apart, so the tap alone isn't where the van was:
# the stop is the van's last real halt (45 s or more) around the tap.
#
# Stops tapped in a burst (TapCheck) aren't matched by time; no-show pickups
# count (the van went and waited); vans with no bus GPS use the tablet's own
# position at an online tap (1.0.31+).
#
# One visit can be wrong (a tap made at the depot, a halt at a light). An address
# gets a "drivers stop here" point only when visits on 3 or more days agree within
# 30 m. If that point is far from the pin, the address goes on Pins to check and
# staff decide (PinChecksController); nothing here moves a pin.
#
# record_day! reads one day of avllog once. The table has no index on unit or
# date, only its row id, which grows with time, so the day's id range is found by
# binary search on the id.
class DriverStops
  STOPPED_KPH  = 1.0     # Pepwave speed when parked reads 0.0
  SAME_SPOT_M  = 25      # a halt drifts a few metres
  MIN_HALT_S   = 45
  BEFORE_TAP   = 15.minutes
  AFTER_TAP    = 3.minutes
  DEPOT_M      = 200
  AGREE_M      = 30
  MIN_DAYS     = 3
  CHECK_FROM_M = 150      # pins further than this from where drivers stop are listed

  Halt = Struct.new(:unit, :from, :to, :lat, :lon, keyword_init: true) do
    def secs = (to - from).to_i
  end

  # -> number of stops recorded for that day (Date, Central)
  def self.record_day!(date, provider: Provider.find(1))
    stops = day_stops(date)
    return 0 if stops.empty?
    halts = with_avl(provider) { |c| halts_for_day(c, date) } || []
    depot = depot_point(provider)
    by_unit = halts.reject { |h| depot && meters(h.lat, h.lon, *depot) < DEPOT_M }.group_by(&:unit)
    done = StopSighting.where(itinerary_id: stops.map(&:id)).pluck(:itinerary_id).to_set
    # Taps made in a burst (TapCheck) don't say when or where the stop was: never
    # matched by time; matched by order only when it is unambiguous.
    by_run = stops.group_by(&:run)
    burst = by_run.flat_map { |_, its| TapCheck.burst_ids(its) }.to_set
    n = stops.count { |i| !done.include?(i.id) && !burst.include?(i.id) && (record_one(i, by_unit) || record_from_tablet(i)) }
    n + by_run.sum { |run, its| sequence_match(run, its, by_unit, done) }
  end

  # Finished pickups/drop-offs that day (and no-show pickups: the van went and
  # waited) on runs with a van.
  def self.day_stops(date)
    day = date.in_time_zone.all_day
    base = Itinerary.joins(:run).includes(:trip, run: :vehicle).where(finish_time: day)
                    .where.not(address_id: nil).where.not(runs: { vehicle_id: nil })
    done = base.where(leg_flag: [1, 2], status_code: Itinerary::STATUS_COMPLETED).to_a
    no_shows = base.where(leg_flag: 1, status_code: Itinerary::STATUS_OTHER).to_a.select { |i| i.trip&.trip_result&.code == 'NS' }
    done + no_shows
  end

  def self.record_one(itin, by_unit)
    unit = itin.run.vehicle&.name.to_s.strip
    tap = itin.finish_time
    halt = (by_unit[unit] || [])
             .select { |h| h.to >= tap - BEFORE_TAP && h.to <= tap + AFTER_TAP && h.from <= tap + AFTER_TAP }
             .min_by { |h| (h.to - tap).abs }
    return false unless halt
    sight!(itin, halt.to, halt.lat, halt.lon, halt.secs, "avl")
  end

  # No bus GPS on this van: the tablet's own position at the tap (1.0.31+), when the
  # tap was made online and the fix is good to 50 m.
  def self.record_from_tablet(itin)
    tap = StopTap.where(itinerary_id: itin.id, action: %w[pickup dropoff noshow arrive]).where.not(latitude: nil)
                 .where("accuracy_m IS NOT NULL AND accuracy_m <= 50").order(:id).detect(&:online?)
    tap ? sight!(itin, tap.tapped_at, tap.latitude, tap.longitude, nil, "tablet") : false
  end

  # Stops tapped in a burst: the van's halts between the last good tap before the
  # burst and the burst itself, paired with the stops in manifest order, but only
  # when there are exactly as many halts as stops. Anything less clear is skipped.
  def self.sequence_match(run, its, by_unit, done)
    unit = run.vehicle&.name.to_s.strip
    halts = by_unit[unit] or return 0
    order = Array(run.manifest_order)
    tapped = its.sort_by(&:finish_time)
    TapCheck.bursts(its).sum do |group|
      next 0 if group.any? { |i| done.include?(i.id) }
      first = group.map(&:finish_time).min
      prev = tapped.select { |i| i.finish_time < first && !group.include?(i) }.last
      from = prev&.finish_time || run.actual_start_time || run.scheduled_start_time
      next 0 unless from
      hs = halts.select { |h| h.from >= from && h.to <= first + AFTER_TAP }.sort_by(&:from)
      next 0 unless hs.size == group.size
      stops = group.sort_by { |i| order.index(i.itin_id) || 10_000 }
      stops.zip(hs).count { |i, h| sight!(i, h.to, h.lat, h.lon, h.secs, "sequence") }
    end
  end

  def self.sight!(itin, at, lat, lon, secs, source)
    StopSighting.create!(address_id: itin.address_id, itinerary_id: itin.id, run_id: itin.run_id,
                         vehicle_id: itin.run.vehicle_id, provider_id: itin.run.provider_id,
                         seen_at: at, dwell_secs: secs, latitude: lat, longitude: lon, source: source)
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end

  # Every halt of every bus on that (Central) day, from one pass over its rows.
  def self.halts_for_day(client, date)
    from_t = date.in_time_zone.beginning_of_day.utc
    to_t = (date + 1).in_time_zone.beginning_of_day.utc + 1.hour
    lo = first_id_at(client, from_t)
    hi = first_id_at(client, to_t)
    return [] if lo.nil? || hi.nil? || hi <= lo
    halts = []
    state = {}
    close = lambda do |unit|
      s = state.delete(unit) or return
      halts << Halt.new(unit: unit, from: s[:from], to: s[:to], lat: s[:slat] / s[:n], lon: s[:slon] / s[:n]) if (s[:to] - s[:from]) >= MIN_HALT_S
    end
    (lo...hi).step(50_000) do |a|
      client.query("SELECT unit, lat, lon, speed, date FROM avllog WHERE idavllog >= #{a.to_i} AND idavllog < #{[a + 50_000, hi].min.to_i} ORDER BY idavllog",
                   stream: true, cache_rows: false, cast: false).each do |r|
        unit = r['unit'].to_s.strip
        lat = r['lat'].to_f; lon = r['lon'].to_f
        next if unit.empty? || lat.zero? || lon.zero?
        t = parse_utc(r['date']) or next
        s = state[unit]
        if r['speed'].to_f < STOPPED_KPH
          if s && t >= s[:to] && (t - s[:to]) <= 120 && meters(s[:alat], s[:alon], lat, lon) <= SAME_SPOT_M
            s[:to] = t; s[:slat] += lat; s[:slon] += lon; s[:n] += 1
          else
            close.(unit)
            state[unit] = { alat: lat, alon: lon, from: t, to: t, slat: lat, slon: lon, n: 1 }
          end
        else
          close.(unit)
        end
      end
    end
    state.keys.each { |u| close.(u) }
    halts
  end

  # Smallest avllog id logged at or after t (ids grow with time).
  def self.first_id_at(client, t)
    lo = client.query("SELECT MIN(idavllog) m FROM avllog").first['m'] or return nil
    hi = client.query("SELECT MAX(idavllog) m FROM avllog").first['m']
    target = t.strftime("%F %T")
    while lo < hi
      mid = (lo + hi) / 2
      row = client.query("SELECT idavllog, date FROM avllog WHERE idavllog >= #{mid} ORDER BY idavllog LIMIT 1").first
      break unless row
      if row['date'].to_s < target then lo = row['idavllog'] + 1 else hi = mid end
    end
    lo
  end

  # ---- what drivers' visits say about an address ----------------------------

  # address_id => { lat:, lon:, days:, visits:, spread_m:, last_seen: } for addresses
  # whose visits agree on 3 or more days.
  def self.learned(address_ids = nil)
    scope = StopSighting.where("seen_at >= ?", 1.year.ago)
    scope = scope.where(address_id: address_ids) if address_ids
    scope.order(:seen_at).group_by(&:address_id).each_with_object({}) do |(aid, ss), out|
      best = ss.max_by { |s| [ss.count { |o| meters(s.latitude, s.longitude, o.latitude, o.longitude) <= AGREE_M }, s.seen_at] }
      near = ss.select { |o| meters(best.latitude, best.longitude, o.latitude, o.longitude) <= AGREE_M }
      days = near.map { |o| o.seen_at.in_time_zone.to_date }.uniq.size
      next if days < MIN_DAYS || near.size * 10 < ss.size * 6     # most visits must agree
      lat = near.sum(&:latitude) / near.size
      lon = near.sum(&:longitude) / near.size
      out[aid] = { lat: lat, lon: lon, days: days, visits: ss.size,
                   spread_m: near.map { |o| meters(lat, lon, o.latitude, o.longitude) }.max.round,
                   last_seen: ss.last.seen_at }
    end
  end

  # Addresses whose pin is far from where drivers stop, not yet decided since the
  # last visit: [{ address:, learned:, distance_m: }], furthest first.
  def self.pins_to_check(provider_ids)
    spots = learned
    return [] if spots.empty?
    decided = PinCheck.where(address_id: spots.keys).group(:address_id).maximum(:created_at)
    saved = saved_place_points
    Address.where(id: spots.keys).where.not(the_geom: nil)
           .where("addresses.provider_id IN (?) OR addresses.customer_id IN (SELECT id FROM customers WHERE provider_id IN (?))", provider_ids, provider_ids)
           .map do |a|
             l = spots[a.id]
             d = meters(a.latitude, a.longitude, l[:lat], l[:lon]).round
             next if d < CHECK_FROM_M
             next if decided[a.id] && decided[a.id] >= l[:last_seen]
             # A driver who always catches up on taps at the next stop (the clinic)
             # would "teach" the clinic for the rider's home: never offer a saved
             # place's spot for someone's home.
             next if a.is_a?(CustomerCommonAddress) && saved.any? { |la, lo| meters(la, lo, l[:lat], l[:lon]) <= 50 }
             { address: a, learned: l, distance_m: d }
           end.compact.sort_by { |x| -x[:distance_m] }
  end

  # ---- helpers ----------------------------------------------------------------

  # Active saved places' pins (a few hundred), for the clinic guard above.
  def self.saved_place_points
    ProviderCommonAddress.where(inactive: [false, nil]).where.not(the_geom: nil).map { |a| [a.latitude, a.longitude] }
  end

  def self.with_avl(provider)
    return nil if provider.busavl_host.blank?
    c = Mysql2::Client.new(host: provider.busavl_host, database: provider.busavl_database.presence || 'busavl',
                           username: provider.busavl_username.presence || ENV['BUSAVL_DB_USERNAME'],
                           password: provider.busavl_password.presence || ENV['BUSAVL_DB_PASSWORD'],
                           connect_timeout: 10, read_timeout: 120)
    yield c
  rescue Mysql2::Error => e
    Rails.logger.warn("[driver stops] AVL unavailable: #{e.class}")
    nil
  ensure
    c&.close
  end

  def self.depot_point(provider)
    g = Address.where(type: 'GarageAddress', provider_id: provider.id).where.not(the_geom: nil).first ||
        Address.where(type: 'GarageAddress').where.not(the_geom: nil).first
    g && [g.latitude, g.longitude]
  end

  def self.parse_utc(s)
    y, mo, d, h, mi, se = s.to_s.scan(/\d+/).map(&:to_i)
    Time.utc(y, mo, d, h, mi, se) if y
  rescue ArgumentError
    nil
  end

  def self.meters(lat1, lon1, lat2, lon2)
    return Float::INFINITY if [lat1, lon1, lat2, lon2].any?(&:nil?)
    p1 = lat1 * Math::PI / 180; p2 = lat2 * Math::PI / 180
    x = Math.sin((p2 - p1) / 2)**2 + Math.cos(p1) * Math.cos(p2) * Math.sin((lon2 - lon1) * Math::PI / 360)**2
    2 * 6_371_000 * Math.asin(Math.sqrt(x))
  end
end
