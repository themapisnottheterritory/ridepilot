require "open-uri"

# Where the Victoria Transit buses are right now, and which route each is on:
# the Victoria tracker's vehicle list (bustracker.gcrpc.org on 10.0.0.32),
# which joins dispatch's Bus Assignments (Fixed) to each bus's last GPS fix.
#
#   LiveBuses.current   # => { "1" => Bus(unit: "1742", route_id: "1", lat:, lon:, at:), ... }
#
# One bus per route: the freshest fix. Assignments that were never switched
# off (a bus on Purple last heard from in June) are ignored by requiring a fix
# in the last few minutes. Fetched at most every 15 seconds; empty if the
# tracker can't be reached, and Next Bus then shows timetable times only.
class LiveBuses
  URL   = ENV.fetch("NEXT_BUS_VEHICLES_URL", "http://10.0.0.32:3003/api/transit/vehicles")
  FRESH = 5.minutes
  CACHE = 15.seconds

  Bus = Struct.new(:unit, :route_id, :lat, :lon, :heading, :speed, :at, keyword_init: true)

  @lock = Mutex.new

  def self.current
    @lock.synchronize do
      if @fetched_at.nil? || @fetched_at < CACHE.ago
        @buses = fetch
        @fetched_at = Time.current
      end
      @buses
    end
  end

  def self.reset! = @lock.synchronize { @fetched_at = nil }

  def self.fetch
    rows = JSON.parse(URI.open(URL, open_timeout: 2, read_timeout: 4).read)
    parse(rows)
  rescue StandardError => e
    Rails.logger.warn("LiveBuses: #{e.class}: #{e.message}")
    {}
  end

  def self.parse(rows, now: Time.current)
    rows.filter_map do |r|
      at = Time.zone.parse(r["gps_time"].to_s) rescue nil
      next unless at && at > now - FRESH && r["route_id"].present? && r["lat"] && r["lon"]
      Bus.new(unit: r["unit"].to_s, route_id: r["route_id"].to_s, lat: r["lat"].to_f, lon: r["lon"].to_f,
              heading: r["heading"], speed: r["speed"].to_f, at: at)
    end.group_by(&:route_id).transform_values { |bs| bs.max_by(&:at) }
  end
end
