# What the driver tablet's sign-in screen says before anyone signs in (Philz,
# 2026-10-01): how many neighbors the whole team (every agency) got where they
# were going on the last service day and over the past week, a milestone when
# there is one, a line of the day (config/driver_welcome_lines.yml), and
# today's weather for Victoria with any National Weather Service alert for our
# counties. Team totals only: no names, no one driver's numbers.
#
# A ride counts when its trip is Complete (FooterNote's rule). The weather is
# fetched by RidePilot from api.weather.gov at most every 30 minutes and kept;
# if the NWS can't be reached, the screen simply has no weather.
class DriverWelcome
  LINES_FILE = Rails.root.join("config", "driver_welcome_lines.yml")
  LAUNCH = Date.new(2026, 10, 1)
  MILESTONE = 1000
  WEATHER_POINT = [28.8053, -97.0036]   # Victoria
  # NWS county zones: Victoria, Calhoun, Jackson, DeWitt, Goliad, Lavaca, Gonzales, Refugio
  ZONES = %w[TXC469 TXC057 TXC239 TXC123 TXC175 TXC285 TXC177 TXC391].freeze
  WEATHER_EVERY = 30.minutes
  AGENT = "GCRPC RidePilot driver tablets (infotech@gcrpc.org)".freeze

  @lock = Mutex.new

  def self.payload(today = Time.zone.today)
    day, count = last_service_day(today)
    week = rides(today - 7, today - 1)
    total = rides(LAUNCH, today - 1)
    {
      rides: { count: count, day: day && day_label(day, today), week: week },
      milestone: milestone(total, count),
      line: line(today),
      weather: weather
    }
  end

  def self.rides(from, to)
    Trip.completed.where(pickup_time: from.in_time_zone.beginning_of_day..to.in_time_zone.end_of_day).count
  end

  # Yesterday, or the last weekday with rides (Monday morning shows Friday).
  def self.last_service_day(today)
    (1..7).each do |back|
      day = today - back
      n = rides(day, day)
      return [day, n] if n > 0
    end
    [nil, 0]
  end

  def self.day_label(day, today)
    day == today - 1 ? "yesterday" : "on #{day.strftime('%A')}"
  end

  # "Yesterday was our 2,000th ride since we started on RidePilot."
  def self.milestone(total, last_day)
    passed = (total / MILESTONE) * MILESTONE
    return nil unless passed >= MILESTONE && total - last_day < passed
    "That took us past #{ActiveSupport::NumberHelper.number_to_delimited(passed)} rides since October 1, 2026."
  end

  def self.line(today)
    lines = Array(YAML.safe_load(File.read(LINES_FILE))).map(&:to_s).reject(&:blank?)
    lines.empty? ? nil : lines[today.jd % lines.size]
  rescue Errno::ENOENT, Psych::SyntaxError
    nil
  end

  def self.weather
    @lock.synchronize do
      if @weather_at.nil? || @weather_at < WEATHER_EVERY.ago
        fresh = fetch_weather
        @weather, @weather_at = fresh, Time.current if fresh || @weather_at.nil?
        @weather_at ||= Time.current
      end
      @weather
    end
  end

  def self.reset! = @lock.synchronize { @weather_at = nil; @weather = nil }

  def self.fetch_weather
    @forecast_url ||= get("https://api.weather.gov/points/#{WEATHER_POINT.join(',')}").dig("properties", "forecast")
    period = Array(get(@forecast_url).dig("properties", "periods")).first
    return nil unless period
    alerts = Array(get("https://api.weather.gov/alerts/active?zone=#{ZONES.join(',')}")["features"]).map { |f| f["properties"] }
    {
      place: "Victoria",
      name: period["name"],                     # "Today", "This Afternoon", "Tonight"
      temp: period["temperature"],
      text: period["shortForecast"],            # "Mostly Sunny", "Chance Showers And Thunderstorms"
      kind: kind(period["shortForecast"], period["isDaytime"]),
      rain: period.dig("probabilityOfPrecipitation", "value"),
      wind: period["windSpeed"],
      alerts: alerts.map { |a| { event: a["event"], until: a["ends"] || a["expires"], severity: a["severity"] } }
                    .uniq { |a| a[:event] }.first(2)
    }
  rescue StandardError => e
    Rails.logger.warn("[driver welcome] weather unavailable: #{e.class}: #{e.message}")
    nil
  end

  # One of the tablet's drawn icons, from the NWS short forecast
  def self.kind(text, day)
    t = text.to_s.downcase
    return "storm" if t.include?("thunder")
    return "rain" if t =~ /rain|shower|drizzle/
    return "fog" if t =~ /fog|haze|smoke/
    return "wind" if t.include?("wind") && t !~ /sunny|clear|cloud/
    return "cloudy" if t =~ /\bcloudy\b|overcast/ && t !~ /partly|mostly sunny/
    return "partly" if t =~ /partly|mostly cloudy|mostly sunny/
    day == false ? "clear-night" : "sunny"
  end

  def self.get(url)
    uri = URI(url)
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 4, read_timeout: 6) do |http|
      http.get(uri.request_uri, "User-Agent" => AGENT, "Accept" => "application/geo+json")
    end
    raise "NWS #{res.code}" unless res.is_a?(Net::HTTPSuccess)
    JSON.parse(res.body)
  end
end
