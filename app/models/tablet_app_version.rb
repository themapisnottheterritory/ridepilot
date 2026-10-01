# Which build of the driver app each tablet is running (Philz, 2026-10-01:
# several tablets downloaded 1.0.19 again and again, and nothing said whether
# they had actually installed it). The Demand Response app sends its version,
# version code and build time with sign-in and as X-App-* headers on every
# request; the last one seen per driver is kept in Redis (no table needed, and
# it survives restarts), and a change is logged as "[tablet app]".
class TabletAppVersion
  KEY = (Rails.env.test? ? "ridepilot:tablet_app_versions:test" : "ridepilot:tablet_app_versions").freeze   # specs share the live Redis

  def self.note(username, version:, code: nil, build: nil, ip: nil)
    return if username.blank? || version.blank?
    seen = { "version" => version.to_s.first(20), "code" => code.to_s.first(10), "build" => build.to_s.first(30) }
    before = find(username)
    same = before && before.slice("version", "code", "build") == seen
    return if same && before["ip"] == ip.to_s && Time.zone.parse(before["at"].to_s).to_i > 10.minutes.ago.to_i   # every request carries it; write at most every 10 min
    redis.hset(KEY, username, seen.merge("ip" => ip.to_s, "at" => Time.current.iso8601).to_json)
    unless same
      Rails.logger.warn("[tablet app] #{username} on #{seen['version']} (code #{seen['code']}, built #{seen['build']}) from #{ip}" +
                        (before ? ", was #{before['version']}" : ""))
    end
  rescue StandardError => e
    Rails.logger.warn("[tablet app] could not record #{username}: #{e.class}: #{e.message}")
  end

  def self.find(username)
    raw = redis.hget(KEY, username)
    raw && JSON.parse(raw)
  end

  # { "jamesc" => {"version"=>"1.0.20", "code"=>"21", "build"=>"...", "ip"=>"...", "at"=>"..."}, ... }
  def self.all
    redis.hgetall(KEY).transform_values { |v| JSON.parse(v) }
  end

  def self.redis
    @redis ||= Redis.new(url: ENV["REDIS_URL"] || "redis://127.0.0.1:6379/0")
  end
end
