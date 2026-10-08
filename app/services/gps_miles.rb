# Miles a bus drove between two times, from its GPS (busavl.avllog on .40,
# read with the agency's busavl_* settings, as the dispatcher map does).
# avllog keeps a fix every few seconds per unit (the bus number) with UTC
# times as text; the index is (date, unit). Jumps faster than 85 mph are GPS
# noise and are dropped, as is jitter while parked.
#
#   gps = GpsMiles.new(provider)
#   gps.miles("1779", t1, t2)   # => 12.4, or nil when the bus has too few fixes
class GpsMiles
  MAX_MPH = 85
  MIN_FIXES = 5
  PARKED_M = 25   # moves this small at speed 0 are jitter

  # Past days don't change: their answers are kept a few months on disk, so a
  # report run again (or a month after the first) doesn't ask the AVL again.
  MEMORY = ActiveSupport::Cache::FileStore.new(Rails.root.join("tmp", "cache", "gps-miles"))

  def initialize(provider, client: nil, memory: MEMORY)
    @provider = provider
    @client = client
    @memory = memory
    @tracks = {}
  end

  def available?
    @provider&.busavl_host.present?
  end

  # Fixes for a unit over a day window, fetched once and kept for the request.
  def miles(unit, from, to)
    return nil if unit.blank? || from.nil? || to.nil? || to <= from || !available?
    return measure(unit, from, to) if to.to_date >= Date.current || @memory.nil?
    key = "#{unit}|#{from.to_i}|#{to.to_i}"
    hit = @memory.read(key)
    return hit[:miles] if hit
    m = measure(unit, from, to)
    @memory.write(key, { miles: m }, expires_in: 120.days)
    m
  end

  # The bus's fixes between two times (moving ones only with moving: true).
  def fixes(unit, from, to, moving: false)
    return [] if unit.blank? || !available?
    track(unit.to_s, from.in_time_zone.to_date).select { |f| f[:t] >= from && f[:t] <= to && (!moving || f[:speed].to_f > 3) }
  rescue StandardError
    []
  end

  private

  def measure(unit, from, to)
    fixes = track(unit.to_s, from.in_time_zone.to_date).select { |f| f[:t] >= from && f[:t] <= to }
    return nil if fixes.size < MIN_FIXES
    total = 0.0
    fixes.each_cons(2) do |a, b|
      m = meters(a, b)
      secs = (b[:t] - a[:t]).to_f
      next if secs <= 0
      next if m / secs * 2.23694 > MAX_MPH
      next if m < PARKED_M && a[:speed].to_f.zero? && b[:speed].to_f.zero?
      total += m
    end
    (total / 1609.344).round(1)
  rescue StandardError => e
    Rails.logger.warn "GpsMiles #{unit}: #{e.class}: #{e.message}"
    nil
  end

  def track(unit, day)
    @tracks[[unit, day]] ||= begin
      from = day.in_time_zone.beginning_of_day.utc
      to = (day + 1).in_time_zone.beginning_of_day.utc + 2.hours
      sql = "SELECT lat, lon, speed, date FROM avllog WHERE date >= '#{from.strftime('%F %T')}' " \
            "AND date < '#{to.strftime('%F %T')}' AND unit = '#{client.escape(unit)}' ORDER BY date"
      client.query(sql).filter_map do |r|
        lat, lon = r["lat"].to_f, r["lon"].to_f
        next if lat.zero? || lon.zero?
        { lat: lat, lon: lon, speed: r["speed"], t: Time.find_zone("UTC").parse(r["date"].to_s) }
      end
    end
  end

  def client
    @client ||= Mysql2::Client.new(host: @provider.busavl_host, database: @provider.busavl_database.presence || "busavl",
                                   username: @provider.busavl_username.presence || ENV["BUSAVL_DB_USERNAME"],
                                   password: @provider.busavl_password.presence || ENV["BUSAVL_DB_PASSWORD"],
                                   connect_timeout: 5, read_timeout: 60)
  end

  def meters(a, b)
    rad = Math::PI / 180
    dlat = (b[:lat] - a[:lat]) * rad
    dlon = (b[:lon] - a[:lon]) * rad
    h = Math.sin(dlat / 2)**2 + Math.cos(a[:lat] * rad) * Math.cos(b[:lat] * rad) * Math.sin(dlon / 2)**2
    2 * 6_371_000 * Math.asin(Math.sqrt(h))
  end
end
