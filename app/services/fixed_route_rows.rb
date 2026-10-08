# The Fixed Route and Commuter rows of RunLogReport. RidePilot's fixed-route
# runs rarely say which bus ran or when, so the times and miles come from GPS:
#
# - City routes: the nightly "published vs driven" build (gcrpc-fixedroute
#   ops/compare-build.py, served at :8080/static/compare/data) lists every
#   trip a bus drove on each route, with its departure and stop times. A
#   row is one bus's block on one route: its trips, split where it sat more
#   than 90 minutes. First pick-up = first trip's departure, last drop-off =
#   last trip's last stop. Start and end of shift = the bus's first and last
#   moving GPS fix within 90 minutes either side (never into another block).
#   Miles are GPS miles; buses have no odometer readings in RidePilot.
# - Commuter routes (2026-10-08): the build matches them too, adding the
#   commuter buses' InControl2 GPS (they don't report to the tracker). Only a
#   few commuter modems have working GPS, so a commuter run the build didn't
#   find carries what RidePilot has (route, date, driver) and says so.
#
# Driver: the RidePilot run for that route and day with a driver, nearest in
# time. Riders: boardings counted on the fixed-route tablet, when there are any.
require "net/http"

class FixedRouteRows
  COMPARE_URL = ENV.fetch("COMPARE_DATA_URL", "http://10.0.0.16:8080/static/compare/data")
  BLOCK_GAP = 90.minutes
  EDGE = 90.minutes

  def initialize(runs, start_date, end_date, gps: nil, compare: nil)
    @runs = runs
    @start_date, @end_date = start_date, end_date
    @gps = gps
    @compare = compare || self.class.fetcher
  end

  # Reads the build's files over HTTP, each once per fetcher (one per report).
  def self.fetcher
    cache = {}
    lambda do |file|
      cache.fetch(file) do
        cache[file] = begin
          uri = URI("#{COMPARE_URL}/#{file}")
          res = Net::HTTP.start(uri.host, uri.port, open_timeout: 3, read_timeout: 30) { |h| h.get(uri.path) }
          res.is_a?(Net::HTTPSuccess) ? JSON.parse(res.body) : nil
        rescue StandardError => e
          Rails.logger.warn "FixedRouteRows compare #{file}: #{e.class}: #{e.message}"
          nil
        end
      end
    end
  end

  attr_reader :commuter_without_data

  def rows
    out = gps_rows
    commuter = @runs.select { |r| r.fixed_route&.kind == "commuter" && !@matched.include?(r.id) }
    # a commuter run with nothing recorded would be a blank row: count it instead
    known, blank = commuter.partition { |r| r.driver_id || r.vehicle_id || r.actual_start_time || r.start_odometer }
    @commuter_without_data = blank.size
    out + known.map { |r| commuter_row(r) }
  end

  private

  def gps_rows
    @matched = Set.new
    blocks = trips_by_block
    blocks.map do |b|
      notes = []
      route_runs = @runs.select { |r| r.date == b[:date] && run_key(r, b[:mode]) == b[:route] }
      # a commuter route has an AM and a PM run: the one on the block's side of noon
      if b[:mode] == "Commuter"
        half = b[:first].hour < 12 ? /\bAM\b/i : /\bPM\b/i
        route_runs = route_runs.select { |r| r.name.to_s.match?(half) }.presence || route_runs
      end
      run = route_runs.select(&:driver).min_by { |r| ((r.scheduled_start_time || r.date.in_time_zone.change(hour: 12)) - b[:first]).abs } || route_runs.first
      @matched.merge(route_runs.map(&:id))
      notes << "Driver not set on the RidePilot run" unless run&.driver
      start_at, end_at = shift_edges(b, blocks)
      notes << "Start or end of shift not seen in GPS" unless start_at && end_at
      rev = @gps&.miles(b[:bus], b[:first], b[:last])
      out = start_at && @gps&.miles(b[:bus], start_at, b[:first])
      back = end_at && @gps&.miles(b[:bus], b[:last], end_at)
      boardings = run ? FixedRouteBoarding.where(run_id: route_runs.map(&:id)).count : 0
      notes << "Riders not counted on the tablet" if boardings.zero?
      notes << "Times and miles from GPS (#{b[:trips]} trips)"
      RunLogReport::Row.new(mode: b[:mode], run_id: run&.id, date: b[:date], driver: run&.driver&.user_name,
                            route: b[:route], bus: b[:bus], start_at: start_at || b[:first], first_pickup_at: b[:first],
                            last_dropoff_at: b[:last], end_at: end_at || b[:last], miles_by: [:gps],
                            revenue_miles_direct: rev, deadhead_miles_direct: (out && back ? (out + back).round(1) : nil),
                            upt: boardings.positive? ? boardings : nil, notes: notes)
    end
  end

  def commuter_row(run)
    RunLogReport::Row.new(mode: "Commuter", run_id: run.id, date: run.date, driver: run.driver&.user_name, route: run.name,
                          bus: run.vehicle&.name, start_at: run.actual_start_time, end_at: run.actual_end_time,
                          start_odo: run.start_odometer, end_odo: run.end_odometer,
                          upt: (n = FixedRouteBoarding.where(run_id: run.id).count).positive? ? n : nil,
                          notes: ["No GPS for this run (the bus's modem doesn't report a position): times and miles not known"])
  end

  # [{date:, route:, bus:, first:, last:, trips:}] for the city routes, by block
  def trips_by_block
    out = []
    index = @compare.call("index.json") || []
    by = Hash.new { |h, k| h[k] = [] }
    index.each do |r|
      next if r["trips"].to_i.zero?
      data = @compare.call("#{r['route_id']}.json") or next
      commuter = r["route_id"].to_s.include?("inteplast")
      # commuter routes go by their short name (RidePilot's route names); city ones by colour
      route = commuter ? r["short_name"].to_s : route_key(r["name"])
      Array(data["trips"]).each do |t|
        day = Date.parse(t["date"]) rescue next
        next if day < @start_date || day >= @end_date
        stops = Array(t["stops"])
        dep = at(day, t["dep"])
        arr = at(day, (stops.last || {})["arr"] || t["dep"])
        by[[day, route, t["bus"].to_s, commuter ? "Commuter" : "Fixed Route"]] << [dep, arr]
      end
    end
    by.each do |(day, route, bus, mode), legs|
      legs.sort!
      block = [legs.first]
      legs.drop(1).each do |leg|
        if leg[0] - block.last[1] > BLOCK_GAP
          out << block_row(day, route, bus, mode, block)
          block = [leg]
        else
          block << leg
        end
      end
      out << block_row(day, route, bus, mode, block)
    end
    out.sort_by { |b| [b[:date], b[:route], b[:first]] }
  end

  def block_row(day, route, bus, mode, legs)
    { date: day, route: route, bus: bus, mode: mode, first: legs.first[0], last: legs.map(&:last).max, trips: legs.size }
  end

  def run_key(run, mode)
    mode == "Commuter" ? run.fixed_route&.name.to_s : route_key(run.fixed_route&.name || run.name)
  end

  # first / last moving fix within EDGE of the block, not into the bus's other blocks
  def shift_edges(b, blocks)
    return [nil, nil] unless @gps
    mine = blocks.select { |o| o[:bus] == b[:bus] && o[:date] == b[:date] && !o.equal?(b) }
    # between two of the bus's blocks, each gets its half of the gap
    lo = [b[:first] - EDGE, *mine.map { |o| o[:last] }.select { |t| t <= b[:first] }.map { |t| t + (b[:first] - t) / 2 }].max
    hi = [b[:last] + EDGE, *mine.map { |o| o[:first] }.select { |t| t >= b[:last] }.map { |t| b[:last] + (t - b[:last]) / 2 }].min
    before = @gps.fixes(b[:bus], lo, b[:first], moving: true)
    after = @gps.fixes(b[:bus], b[:last], hi, moving: true)
    [before.first&.dig(:t)&.in_time_zone, after.last&.dig(:t)&.in_time_zone]
  end

  def at(day, secs)
    day.in_time_zone.beginning_of_day + secs.to_i.seconds
  end

  # "Blue Northbound (FY2027)" and the RidePilot route "Blue" both -> "Blue"
  def route_key(name)
    name.to_s[/\A[A-Za-z]+/].to_s.capitalize
  end

end
