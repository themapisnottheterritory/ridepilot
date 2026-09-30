require "open-uri"

# Next Bus: "I'm at Mockingbird and Navarro, when's the next bus?"
#
#   NextBus.new.lookup("mockingbird and navarro")
#   # => { place: {label:, lat:, lon:, how:}, others: [...], stops: [...], say: "The next Pink bus ..." }
#
# 1. Where is the caller? Stop names first (they are written as corners, "N
#    Navarro @ E Mockingbird (Northbound)"), then two streets that cross, then
#    the map search for a landmark or address.
# 2. The stops within a few minutes' walk, with the next three buses for each
#    route and direction, from the published timetable (FixedRouteSchedule).
# 3. Live: when dispatch has a bus on that route and it has reported in the
#    last few minutes (LiveBuses), where it is along its trip, how late it is,
#    and so when it will really reach the stop.
class NextBus
  WALK_MILES   = 0.4    # about 8 minutes on foot
  WALK_MIN_PER_MILE = 20
  PER_ROUTE    = 3      # departures per route and direction at a stop
  ON_ROUTE_M   = 150    # a bus further than this from its route's line isn't running it
  LOOKBACK     = 30.minutes   # a late bus can still be coming to a stop whose time has passed
  NOMINATIM    = ENV["NOMINATIM_URL"] || "http://10.0.0.18:8088"
  TOWN         = "Victoria"

  Live = Struct.new(:bus, :trip, :along, :delay, :score, keyword_init: true)

  def initialize(schedule: FixedRouteSchedule.current, buses: LiveBuses.current, now: Time.zone.now)
    @s, @buses, @now = schedule, buses, now
  end

  def lookup(text)
    places = find_places(text.to_s.strip)
    place = places.first or return { place: nil, others: [], stops: [], say: nil }
    stops = stops_near(place[:lat], place[:lon])
    { place: place, others: places.drop(1).first(4), stops: stops, say: sentence(stops) }
  end

  def at(lat, lon, label)
    place = { label: label, lat: lat.to_f, lon: lon.to_f, how: "map" }
    stops = stops_near(place[:lat], place[:lon])
    { place: place, others: [], stops: stops, say: sentence(stops) }
  end

  # ---- where is the caller ----

  def find_places(text)
    return [] if text.length < 2
    named = @s.stops_named(text)
    if named.any?
      corners = named.group_by(&:corner)
      return corners.map do |corner, ss|
        { label: corner, lat: ss.sum(&:lat) / ss.size, lon: ss.sum(&:lon) / ss.size, how: "stop" }
      end
    end
    marks = landmark_places(text)
    return marks if marks.any?
    a, b = text.split(/\s+(?:and|&|@|at|y)\s+|\s*[&@\/]\s*/i, 2)
    if b.present? && (x = crossing(a, b))
      return [x]
    end
    search(text)
  end

  # "I'm at the Whataburger on Navarro": landmarks whose every word was said,
  # best first by how many of the other words match the stop's name (Navarro).
  def landmark_places(text)
    said = landmark_words(text)
    return [] if said.empty?
    hits = StopLandmark.shown.to_a.filter_map do |lm|
      words = landmark_words(lm.name)
      next if words.empty? || !(words - said).empty?
      stop = @s.stops[lm.stop_id] or next
      rest = said - words
      # more of the words said: the landmark's own ("HEB pharmacy" is the
      # pharmacy, not the H-E-B), then the stop's street ("on Navarro")
      [[words.size, rest.count { |w| stop.name.downcase.include?(w) }], lm, stop]
    end
    return [] if hits.empty?
    best = hits.map(&:first).max
    hits.select { |score, _, _| score == best }.uniq { |_, lm, _| [lm.name.downcase, (lm.lat.to_f * 500).round, (lm.lon.to_f * 500).round] }.map do |_, lm, stop|
      { label: "#{lm.name} (#{stop.corner})", lat: (lm.lat || stop.lat).to_f, lon: (lm.lon || stop.lon).to_f, how: "landmark" }
    end
  end

  # "H-E-B", "HEB" and "H E B" are the same word; so are "McDonald's" and "mcdonalds"
  def landmark_words(text)
    text.downcase.gsub(/(?<=\b[a-z])[\s.-](?=[a-z]\b)/, "").gsub(/['’.-]/, "").scan(/[a-z0-9]+/) - FixedRouteSchedule::IGNORED_WORDS
  end

  # Two streets that cross: their lines from the map, and the closest pair of
  # points between them.
  def crossing(a, b)
    la, lb = street_points(a), street_points(b)
    return nil if la.empty? || lb.empty?
    best = la.product(lb).min_by { |p, q| (p[0] - q[0])**2 + (p[1] - q[1])**2 }
    return nil if FixedRouteSchedule.miles(*best[0], *best[1]) > 0.05
    { label: "#{a.strip.titleize} & #{b.strip.titleize}", lat: (best[0][0] + best[1][0]) / 2, lon: (best[0][1] + best[1][1]) / 2, how: "corner" }
  end

  def street_points(name)
    nominatim(street: name.strip, city: TOWN, state: "TX", polygon_geojson: 1, limit: 5).flat_map do |hit|
      g = hit["geojson"] or next []
      case g["type"]
      when "LineString" then g["coordinates"].map { |lon, lat| [lat, lon] }
      when "MultiLineString" then g["coordinates"].flatten(1).map { |lon, lat| [lat, lon] }
      else []
      end
    end
  end

  def search(text)
    q = text =~ /victoria/i ? text : "#{text}, #{TOWN}, TX"
    nominatim(q: q, limit: 5).map do |hit|
      label = hit["display_name"].to_s.split(", ").first(3).join(", ")
      { label: label, lat: hit["lat"].to_f, lon: hit["lon"].to_f, how: "map" }
    end.uniq { |p| p[:label] }
  end

  def nominatim(params)
    query = { format: "json", countrycodes: "us", viewbox: "-97.12,28.92,-96.88,28.72", bounded: 1 }.merge(params)
    JSON.parse(URI.open("#{NOMINATIM}/search?#{query.to_query}", open_timeout: 3, read_timeout: 6).read)
  rescue StandardError => e
    Rails.logger.warn("NextBus nominatim: #{e.class}: #{e.message}")
    []
  end

  # ---- stops and buses ----

  def stops_near(lat, lon)
    seen = {}
    near = @s.stops_near(lat, lon, miles: WALK_MILES)
    marks = StopLandmark.for_stops(near.map { |stop, _| stop.id })
    near.map do |stop, miles|
      # a route and direction shows at the nearest stop that has it; further
      # along the same street it's the same bus a minute earlier or later
      rows = @s.departures(stop.id, @now - LOOKBACK).filter_map { |dep| estimate(dep) }
                .reject { |r| seen.key?([r[:route_id], r[:direction_id]]) && seen[[r[:route_id], r[:direction_id]]] != stop.id }
      rows.each { |r| seen[[r[:route_id], r[:direction_id]]] ||= stop.id }
      groups = rows.group_by { |r| [r[:route_id], r[:direction_id]] }.map do |_, rs|
        rs = rs.sort_by { |r| r[:at] }.first(PER_ROUTE)
        rs.first.slice(:route_id, :route, :color, :text_color, :headsign, :direction_id).merge(buses: rs.map { |r| r.except(:route_id, :route, :color, :text_color, :headsign, :direction_id) })
      end.sort_by { |g| g[:buses].first[:at] }
      { id: stop.id, code: stop.code, name: stop.name, corner: stop.corner, side: stop.side, lat: stop.lat, lon: stop.lon,
        miles: miles.round(2), walk_min: (miles * WALK_MIN_PER_MILE).ceil, routes: groups, landmarks: (marks[stop.id] || []).map(&:as_json) }
    end.reject { |s| s[:routes].empty? }
  end

  # One departure, with the live estimate when there is one; nil when it has
  # already gone (by the timetable, or by where the bus is).
  def estimate(dep)
    live = live_for(dep.trip)
    # at the end of the line the bus turns around: it's the next trip's direction
    onward = dep.turns_into || dep.trip
    base = { route_id: dep.route.id, route: dep.route.name, color: dep.route.color, text_color: dep.route.text_color,
             headsign: onward.headsign, direction_id: onward.direction_id, turns_here: !!dep.turns_into,
             continues_from: dep.turns_into && @s.stops[dep.turns_into.times.first.stop_id]&.name,
             scheduled: dep.at, last: !!dep.last_of_day,
             tomorrow: dep.date != @now.to_date, day: dep.date }
    if live && dep.date == @now.to_date && live_trip?(live, dep.trip) && (ahead = stops_ahead(live, dep))
      return nil if ahead < 0   # the bus has passed this stop
      # lateness carries to the bus's later trips, less the break at the end of the line
      slack = dep.trip.id == live.trip.id ? 0 : dep.trip.first_sec - live.trip.last_sec
      late = [live.delay - slack, 0].max
      predicted = dep.at + late.seconds
      predicted = [predicted, @now].max
      base.merge(at: predicted, live: true, unit: live.bus.unit, delay_min: (late / 60.0).round, early_min: (live.delay < -60 ? (-live.delay / 60.0).round : 0), stops_away: ahead)
    else
      return nil if dep.at < @now - 1.minute
      base.merge(at: dep.at, live: false)
    end.then { |r| r.merge(in_min: ((r[:at] - @now) / 60.0).ceil.clamp(0, 10_000)) }
  end

  # How many stops away the bus is from this departure's stop (0: it's the
  # bus's next stop), -1 if it has passed it, nil if the live bus isn't on
  # this trip or an earlier one of the same block.
  def stops_ahead(live, dep)
    idx = dep.trip.times.index(dep.stop_time)
    if dep.trip.id == live.trip.id
      return -1 if dep.stop_time.dist <= live.along
      return dep.trip.times[0..idx].count { |st| st.dist > live.along } - 1
    end
    return nil unless later_on_block?(live, dep.trip)
    left_now = live.trip.times.count { |st| st.dist > live.along }
    between = @s.trips.values.select { |t| later_on_block?(live, t) && t.first_sec < dep.trip.first_sec }
    left_now + between.sum { |t| t.times.size - 1 } + idx - 1
  end

  # live only for the trip the bus is on and its next one; hours ahead the
  # timetable is as good a guess as any
  def live_trip?(live, trip)
    trip.id == live.trip.id || @s.next_on_block(live.trip, @now.to_date)&.id == trip.id
  end

  def later_on_block?(live, trip)
    trip.block_id == live.trip.block_id && trip.first_sec >= live.trip.last_sec && @s.running?(trip.service_id, @now.to_date)
  end

  # The live position of the bus on this trip's route, placed on its trip:
  # which trip of the block it is running, how far along, and how late.
  #
  # Keyed by block: one timetabled bus can run two routes in turn (Gold then
  # Green, block 4-5_C1), and dispatch may have either route's bus assigned,
  # so each bus assigned to a route of the block is tried and the one found
  # on the line wins.
  def live_for(trip)
    @live ||= {}
    return @live[trip.block_id] if @live.key?(trip.block_id)
    routes = @s.trips.values.select { |t| t.block_id == trip.block_id }.map(&:route_id).uniq
    placed = routes.filter_map { |r| @buses[r] && place_bus(@buses[r], trip.block_id) }
    @live[trip.block_id] = placed.min_by(&:score)
  end

  def place_bus(bus, block_id)
    today = @now.to_date
    midnight = @now.beginning_of_day
    now_sec = (@now - midnight).to_i
    candidates = @s.trips.values.select do |t|
      t.block_id == block_id && @s.running?(t.service_id, today) && now_sec.between?(t.first_sec - 15 * 60, t.last_sec + 45 * 60)
    end
    best = nil
    candidates.each do |t|
      shape = @s.shapes[t.shape_id]
      next if shape.size < 2
      shape.each_cons(2) do |p, q|
        d, f = self.class.to_segment(bus.lat, bus.lon, p, q)
        next if d > ON_ROUTE_M
        # parked at the first stop a few metres short of where the line starts
        along = (p[2] + f * (q[2] - p[2])).clamp(t.times.first.dist, t.times.last.dist)
        sched = sched_at(t, along)
        score = (now_sec - sched).abs + d
        best = [score, t, along, now_sec - sched] if best.nil? || score < best[0]
      end
    end
    best && Live.new(bus: bus, trip: best[1], along: best[2], delay: best[3], score: best[0])
  end

  # timetable seconds at a distance along the trip, between its stops
  def sched_at(trip, along)
    trip.times.each_cons(2) do |a, b|
      next unless along.between?(a.dist, b.dist)
      span = b.dist - a.dist
      return a.arr + (span > 0 ? (along - a.dist) / span * (b.arr - a.arr) : 0)
    end
    along <= trip.times.first.dist ? trip.first_sec : trip.last_sec
  end

  # metres from a point to the segment p-q, and how far along it (0..1)
  def self.to_segment(lat, lon, p, q)
    k = Math.cos(lat * Math::PI / 180)
    m = 111_320.0
    px, py = (p[1] - lon) * k * m, (p[0] - lat) * m
    qx, qy = (q[1] - lon) * k * m, (q[0] - lat) * m
    dx, dy = qx - px, qy - py
    len2 = dx * dx + dy * dy
    f = len2.zero? ? 0.0 : (-(px * dx + py * dy) / len2).clamp(0.0, 1.0)
    cx, cy = px + f * dx, py + f * dy
    [Math.sqrt(cx * cx + cy * cy), f]
  end

  # ---- what to say ----

  def sentence(stops)
    first = stops.flat_map { |s| s[:routes].map { |g| [s, g, g[:buses].first] } }.min_by { |s, _, b| b[:at] + s[:walk_min].minutes }
    return nil unless first
    stop, g, b = first
    when_ = b[:tomorrow] ? "#{b[:day] == @now.to_date + 1 ? 'tomorrow' : b[:day].strftime('%A')} at #{clock(b[:at])}" : "at #{clock(b[:at])}, in about #{pluralize_min(b[:in_min])}"
    live = if b[:live]
      b[:delay_min] > 1 ? ", running about #{pluralize_min(b[:delay_min])} late" : ", on time"
    end
    by = stop[:landmarks]&.find { |lm| lm[:meters].nil? || lm[:meters] <= NEAR_LANDMARK_M }
    "The next #{g[:route]} bus toward #{spoken(g[:headsign], place: true)}, from the stop at #{spoken(stop[:corner])}#{", #{stop[:side].downcase.sub(/ side\z/, '')} side" if stop[:side]}#{", by the #{by[:name]}" if by}, is #{when_}#{live}."
  end

  NEAR_LANDMARK_M = 100   # close enough to say "by the Whataburger"

  # For reading out: "@" between two streets is "and" ("N Navarro and E
  # Mockingbird"), before a place it's "at" ("Victoria Mall at Cinemark").
  STREETISH = /\A(?:N|S|E|W|NE|NW|SE|SW)\s|\b(?:St|Street|Ave|Rd|Blvd|Dr|Hwy|Ln|Loop|Pkwy)\b/
  def spoken(name, place: false)
    name.to_s.gsub(/\s*@\s*(\S[^@]*)/) { rest = Regexp.last_match(1); " #{!place && rest.match?(STREETISH) ? 'and' : 'at'} #{rest}" }
  end

  def clock(t) = t.strftime("%-l:%M %p").sub(":00 ", " ")
  def pluralize_min(n) = n.to_i == 1 ? "1 minute" : "#{n.to_i} minutes"
end
