require "open-uri"
require "zip"
require "csv"

# The published Victoria Transit city timetable (the GTFS feed riders' apps
# and the Victoria tracker use), held in memory for Next Bus.
#
#   s = FixedRouteSchedule.current
#   s.stops_near(28.8352, -97.0015, miles: 0.4)   # => [[stop, miles], ...]
#   s.departures("46", Time.zone.now)             # => [Departure, ...]
#
# The feed is small (160-odd stops, under 100 trips), so it is read whole and
# re-read every hour; if a download fails the last good copy stays in use.
# Times are seconds after local midnight of the service day (GTFS allows
# past 24:00 for trips that run over midnight).
class FixedRouteSchedule
  FEED_URL = ENV.fetch("NEXT_BUS_GTFS_URL", "https://gtfs.gcrpc.org/gtfs/GCRPC-Fixed.zip")
  REFRESH  = 1.hour

  Stop      = Struct.new(:id, :code, :name, :lat, :lon, keyword_init: true) do
    # "N Navarro @ E Mockingbird (Northbound)" -> "N Navarro @ E Mockingbird"
    def corner = name.sub(/\s*\([^)]*\)\s*\z/, "")
    def side   = name[/\(([^)]*)\)\s*\z/, 1]
  end
  Route     = Struct.new(:id, :name, :color, :text_color, :desc, :sort, keyword_init: true)
  Trip      = Struct.new(:id, :route_id, :service_id, :headsign, :direction_id, :block_id, :shape_id, :times, keyword_init: true) do
    def first_sec = times.first.arr
    def last_sec  = times.last.arr
  end
  StopTime  = Struct.new(:stop_id, :seq, :arr, :dist, keyword_init: true)
  Departure = Struct.new(:trip, :route, :stop_time, :date, :at, :last_of_day, :turns_into, keyword_init: true)
  Fare      = Struct.new(:id, :price, keyword_init: true)

  attr_reader :stops, :routes, :trips, :shapes, :fares, :loaded_at, :feed_version

  @lock = Mutex.new

  def self.current
    @lock.synchronize do
      if @current.nil? || @current.loaded_at < REFRESH.ago
        begin
          @current = from_zip(URI.open(FEED_URL, open_timeout: 5, read_timeout: 20).read)
        rescue StandardError => e
          Rails.logger.warn("FixedRouteSchedule: #{e.class}: #{e.message}")
          raise if @current.nil?
          @current.instance_variable_set(:@loaded_at, Time.current)   # try again in an hour
        end
      end
      @current
    end
  end

  def self.reset! = @lock.synchronize { @current = nil }

  # files: { "stops.txt" => "csv text", ... }
  def self.from_zip(bytes)
    files = {}
    Zip::File.open_buffer(StringIO.new(bytes)) do |zip|
      zip.each { |e| files[File.basename(e.name)] = e.get_input_stream.read.force_encoding("UTF-8") if e.file? }
    end
    new(files)
  end

  def initialize(files)
    rows = ->(name) { files[name] ? CSV.parse(files[name].sub(/\A﻿/, ""), headers: true).map(&:to_h) : [] }
    hms  = ->(t) { h, m, s = t.to_s.split(":").map(&:to_i); h * 3600 + m * 60 + s.to_i }

    @stops  = rows.("stops.txt").to_h { |r| [r["stop_id"], Stop.new(id: r["stop_id"], code: r["stop_code"], name: r["stop_name"].to_s.strip, lat: r["stop_lat"].to_f, lon: r["stop_lon"].to_f)] }
    @routes = rows.("routes.txt").to_h do |r|
      [r["route_id"], Route.new(id: r["route_id"], name: r["route_long_name"].presence || r["route_short_name"], color: "##{r['route_color'].presence || '1f3864'}",
                                text_color: "##{r['route_text_color'].presence || 'ffffff'}", desc: r["route_desc"], sort: r["route_sort_order"].to_i)]
    end
    times = Hash.new { |h, k| h[k] = [] }
    rows.("stop_times.txt").each do |r|
      times[r["trip_id"]] << StopTime.new(stop_id: r["stop_id"], seq: r["stop_sequence"].to_i, arr: hms.(r["arrival_time"].presence || r["departure_time"]), dist: r["shape_dist_traveled"].to_f)
    end
    @trips = rows.("trips.txt").to_h do |r|
      [r["trip_id"], Trip.new(id: r["trip_id"], route_id: r["route_id"], service_id: r["service_id"], headsign: r["trip_headsign"], direction_id: r["direction_id"].to_i,
                              block_id: r["block_id"], shape_id: r["shape_id"], times: times[r["trip_id"]].sort_by(&:seq))]
    end
    @trips.reject! { |_, t| t.times.empty? }
    @by_stop = Hash.new { |h, k| h[k] = [] }
    @trips.each_value { |t| t.times.each_with_index { |st, i| @by_stop[st.stop_id] << [t, i] } }
    @shapes = Hash.new { |h, k| h[k] = [] }
    rows.("shapes.txt").sort_by { |r| [r["shape_id"], r["shape_pt_sequence"].to_i] }.each do |r|
      @shapes[r["shape_id"]] << [r["shape_pt_lat"].to_f, r["shape_pt_lon"].to_f, r["shape_dist_traveled"].to_f]
    end
    @calendar = rows.("calendar.txt").to_h { |r| [r["service_id"], r] }
    @exceptions = rows.("calendar_dates.txt").group_by { |r| r["date"] }
    @fares = rows.("fare_attributes.txt").map { |r| Fare.new(id: r["fare_id"], price: r["price"].to_d) }
    @feed_version = rows.("feed_info.txt").first&.dig("feed_version")
    @loaded_at = Time.current
  end

  # Is this service (e.g. "weekday") running on this date? calendar.txt, then
  # calendar_dates.txt exceptions (holidays removed, extra days added).
  def running?(service_id, date)
    ex = (@exceptions[date.strftime("%Y%m%d")] || []).find { |r| r["service_id"] == service_id }
    return ex["exception_type"] == "1" if ex
    c = @calendar[service_id] or return false
    ymd = date.strftime("%Y%m%d")
    ymd >= c["start_date"].to_s && ymd <= c["end_date"].to_s && c[date.strftime("%A").downcase] == "1"
  end

  def trips_on(date) = @trips.values.select { |t| running?(t.service_id, date) }

  # [[stop, miles]] nearest first
  def stops_near(lat, lon, miles: 0.4, limit: 8)
    @stops.values.map { |s| [s, self.class.miles(lat, lon, s.lat, s.lon)] }
          .select { |_, d| d <= miles }.sort_by(&:last).first(limit)
  end

  # Stops whose name has every word typed ("mockingbird navarro" matches
  # "N Navarro @ E Mockingbird (Northbound)"). Street-type words and
  # directions are ignored so "Navarro St" still matches.
  IGNORED_WORDS = %w[and at the st street rd road ave avenue blvd dr drive ln n s e w north south east west hwy highway of by near corner].freeze
  def stops_named(text)
    words = text.downcase.scan(/[a-z0-9]+/) - IGNORED_WORDS
    return [] if words.empty?
    @stops.values.select { |s| n = s.name.downcase; words.all? { |w| n =~ /\b#{Regexp.escape(w)}/ } }
  end

  # Departures from a stop after `from` (a time), for today's service and, if
  # nothing is left today, the next day the service runs. The last stop of a
  # trip (the end of the line) counts when the same bus has another trip that
  # starts somewhere else: turns_into is that trip. (Blue ends at Citizens
  # HealthPlex and starts back from Victoria Mall.)
  def departures(stop_id, from, days_ahead: 7)
    out = []
    (0..days_ahead).each do |d|
      date = from.to_date + d
      midnight = from.in_time_zone.beginning_of_day + d.days
      after = d.zero? ? (from - midnight).to_i : 0
      todays = @by_stop[stop_id].filter_map do |trip, i|
        next unless running?(trip.service_id, date)
        st = trip.times[i]
        next if st.arr < after
        turns = nil
        if i == trip.times.size - 1
          turns = next_on_block(trip, date)
          # the same bus's next trip starts here: that departure is listed already
          next if turns.nil? || turns.times.first.stop_id == st.stop_id
        end
        Departure.new(trip: trip, route: @routes[trip.route_id], stop_time: st, date: date, at: midnight + st.arr, turns_into: turns)
      end
      next if todays.empty? && d.zero?
      # last bus of the day, per route and direction, at this stop
      last = @by_stop[stop_id].select { |t, i| running?(t.service_id, date) && (i < t.times.size - 1 || next_on_block(t, date)) }
                               .group_by { |t, _| [t.route_id, t.direction_id] }.transform_values { |v| v.map { |t, i| t.times[i].arr }.max }
      todays.each { |dep| dep.last_of_day = dep.stop_time.arr == last[[dep.trip.route_id, dep.trip.direction_id]] }
      out.concat(todays)
      break if todays.any?
    end
    out.sort_by(&:at)
  end

  # the bus's next trip after this one, the same day
  def next_on_block(trip, date)
    @next_on_block ||= {}
    @next_on_block[[trip.id, date]] ||= @trips.values.select { |t| t.block_id == trip.block_id && t.first_sec >= trip.last_sec && running?(t.service_id, date) }
                                              .min_by(&:first_sec) || false
    @next_on_block[[trip.id, date]] || nil
  end

  def self.miles(lat1, lon1, lat2, lon2)
    rad = ->(x) { x * Math::PI / 180 }
    a = Math.sin(rad.(lat2 - lat1) / 2)**2 + Math.cos(rad.(lat1)) * Math.cos(rad.(lat2)) * Math.sin(rad.(lon2 - lon1) / 2)**2
    2 * 3958.8 * Math.asin(Math.sqrt(a))
  end
end
