# A driver tablet, as the Demand Response app (1.0.24+) reports it every ten
# minutes and on wake (Philz 2026-10-02: "a tablet management page ... all the
# info a technician would want"). One row per device (Android ID), the whole
# latest report in `info`, and a light history in tablet_pings for battery,
# connection and use. Numbered from the WireGuard address: 10.99.0.(NN+10)
# is tablet-NN. Tablets page: TabletsController.
class Tablet < ActiveRecord::Base
  has_many :pings, class_name: "TabletPing", dependent: :delete_all

  ONLINE_FOR = 15.minutes
  OUR_DR  = "org.gcrpc.transit.demandresponse".freeze
  OUR_FR  = "org.gcrpc.transit.fixedroute".freeze
  WIREGUARD = "com.wireguard.android".freeze
  OLD_APPS = { "com.victoriatransit.rideavl" => "RideAVL", "com.victoriatransit.rideavl.training" => "RideAVL Training",
               "org.gcrpc.fixedroute.driver" => "GCRPC Driver" }.freeze
  OTHER_APPS = { "com.yukti.shah.driver" => "Driver-Connect", "com.saferideapp.app" => "SafeRide Driver",
                 "org.gcrpc.transit.fixedroute.test" => "Fixed Route (test build)" }.freeze

  scope :by_number, -> { order(Arel.sql("number is null, number, last_seen_at desc")) }

  # Who may open Vehicles > Tablets: GCRPC admins, system admins, and these
  # people by username without making them admins (Philz 2026-10-02: Shelby).
  EXTRA_VIEWERS = %w[shelbyw].freeze

  def self.viewer?(user)
    return false unless user
    user.super_admin? || EXTRA_VIEWERS.include?(user.username.to_s.downcase) ||
      user.roles.where(provider_id: 1).where("level >= ?", Role::ADMIN_LEVEL).exists?
  end

  # Store one report. `ip` is what nginx saw: a 10.99.0.x address names the tablet;
  # off the tunnel (office Wi-Fi) the app's own tunnel name stands in.
  def self.record!(report:, app:, ip:)
    dev = report["device"] || {}
    android_id = dev["androidId"].to_s.strip
    raise ArgumentError, "no androidId" if android_id.blank?
    tablet = find_or_initialize_by(android_id: android_id)
    now = Time.current
    number = number_from_ip(ip) || number_from_tunnel(app["tunnel"]) || tablet.number
    # Both apps report (Fixed Route 1.16 sends name "fixed"); they share the fleet key, so the
    # same Android ID and one row. app_version/app_code stay Demand Response's; each app's own
    # answer is kept under by_app, and "app" is whichever reported last.
    fixed = app["name"] == "fixed"
    by_app = (tablet.info["by_app"] || {}).merge(fixed ? "fixed" : "dr" => app.merge("at" => now.iso8601, "setup" => report["setup"]))
    attrs = { number: number, manufacturer: dev["manufacturer"], model: dev["model"], android_version: dev["android"],
              sdk: dev["sdk"], username: app["username"].presence || tablet.username,
              last_ip: ip, info: report.merge("app" => app, "by_app" => by_app, "received_at" => now.iso8601),
              first_seen_at: tablet.first_seen_at || now, last_seen_at: now }
    if fixed
      attrs[:app_version] ||= tablet.app_version || report.dig("apps", OUR_DR, "version")
      attrs[:app_code] ||= tablet.app_code || report.dig("apps", OUR_DR, "code")
    else
      attrs.merge!(app_version: app["version"], app_code: app["code"])
    end
    tablet.assign_attributes(attrs)
    tablet.save!
    net = report["network"] || {}
    tablet.pings.create!(at: now, battery: report.dig("battery", "percent"), charging: report.dig("battery", "charging"),
      network: net["wifi"] ? "wifi" : net["cellular"] ? "cell" : "none", vpn: net["vpn"], connection: app["connection"],
      app_version: fixed ? "FR #{app['version']}" : app["version"], username: app["username"].presence,
      storage_free_mb: report.dig("storage", "freeMB"))
    tablet
  end

  # Behind the published release, per app: { "dr" => true/false, "fixed" => ... } for the apps it has.
  def behind
    pub = self.class.published
    out = {}
    if (c = apps.dig(OUR_DR, "code")) && pub[:dr] then out["dr"] = c.to_i < pub[:dr]["code"] end
    if (c = apps.dig(OUR_FR, "code")) && pub[:fr] then out["fixed"] = c.to_i < pub[:fr]["code"] end
    out
  end

  def behind?; behind.values.any?; end

  # GCRPC I.T. asked it to update (Tablets page); the next report from an app that is
  # behind answers update: true. Done once nothing it has is behind any more.
  def ask_to_update!(by)
    update!(update_requested_at: Time.current, update_requested_by: by, update_done_at: nil)
  end

  def update_wanted?(app_name)
    update_requested_at.present? && behind[app_name == "fixed" ? "fixed" : "dr"] == true
  end

  def settle_update_request!
    update!(update_requested_at: nil, update_done_at: Time.current) if update_requested_at && !behind?
  end

  def self.number_from_ip(ip)
    m = ip.to_s.match(/\A10\.99\.0\.(\d+)\z/)
    m && m[1].to_i > 10 ? m[1].to_i - 10 : nil
  end

  def self.number_from_tunnel(name)
    m = name.to_s.match(/\Atablet-(\d+)\z/)
    m && m[1].to_i
  end

  # What's published now, to say who is behind: { dr: {version, code}, fr: {...} }
  def self.published
    Rails.cache.fetch("tablets:published:v2", expires_in: 5.minutes) do
      dr = JSON.parse(File.read(Rails.root.join("public", "gcrpc-demandresponse-version.json"))) rescue nil
      fr = begin
        JSON.parse(Net::HTTP.get(URI(ENV.fetch("FIXED_ROUTE_RELEASE_URL", "http://10.0.0.16:8080/static/apk/gcrpc-fixedroute-version.json"))))
      rescue StandardError
        nil
      end
      at = ->(j) { Time.zone.parse(j["published_at"].to_s) rescue nil }
      { dr: dr && { "version" => dr["version"], "code" => dr["version_code"].to_i, "published_at" => at.(dr) },
        fr: fr && { "version" => fr["version"], "code" => fr["version_code"].to_i, "published_at" => at.(fr) } }
    end
  end

  def label
    number ? format("tablet-%02d", number) : "unnumbered #{android_id.first(6)}"
  end

  def online?
    last_seen_at.present? && last_seen_at > ONLINE_FOR.ago
  end

  def device;  info["device"]  || {}; end
  def battery; info["battery"] || {}; end
  def storage; info["storage"] || {}; end
  def network; info["network"] || {}; end
  def apps;    info["apps"]    || {}; end
  def setup;   info["setup"]   || {}; end
  def app_info; info["app"]    || {}; end

  # Permissions are each app's own: { "Demand Response" => setup, "Fixed Route" => setup }.
  # Reports from before both apps reported carry one setup, the last app's.
  def per_app_setup
    names = { "dr" => "Demand Response", "fixed" => "Fixed Route" }
    seen = (info["by_app"] || {}).select { |_, a| a["setup"] }.map { |k, a| [names[k] || k, a["setup"]] }.to_h
    seen.presence || { (app_info["name"] == "fixed" ? "Fixed Route" : "Demand Response") => setup }
  end

  # WireGuard remote control as the apps last tested it: on if either app found it on.
  def remote_control
    states = (info["by_app"] || {}).values.map { |a| a["remote"] } + [app_info["remote"]]
    states.include?("on") ? "on" : (states.include?("off") ? "off" : "untested")
  end

  def fr_version; apps.dig(OUR_FR, "version"); end
  def old_apps;   OLD_APPS.select { |pkg, _| apps[pkg] }.values; end

  # Device clock minus server clock at the report, in seconds (a wrong clock breaks sign-in and times).
  def clock_skew
    t = device["deviceTime"].to_i
    r = info["received_at"].presence && Time.zone.parse(info["received_at"])
    t.positive? && r ? (t / 1000.0 - r.to_f).round : nil
  end

  # Things a technician should look at, worst first: [[:crit|:warn, "text"], ...]
  def issues
    out = []
    pub = self.class.published
    out << [:crit, "Not seen for #{ApplicationController.helpers.time_ago_in_words(last_seen_at)}"] if last_seen_at && last_seen_at < 24.hours.ago
    out << [:crit, "Old app#{'s' if old_apps.size > 1} still installed: #{old_apps.join(', ')}"] if old_apps.any?
    if update_requested_at
      out << [:warn, "Asked to update #{update_requested_at.in_time_zone.strftime('%b %-d %-l:%M %p')}#{" by #{update_requested_by}" if update_requested_by}, not done yet"]
    end
    out << [:crit, "WireGuard is not installed"] if setup.key?("wireguard") && !setup["wireguard"]
    waiting = (info["by_app"] || {}).dig("dr", "pending_taps").to_i
    out << [:warn, "#{waiting} stop tap#{'s' if waiting > 1} saved on the tablet, waiting to send"] if waiting.positive?
    if pub[:dr] && app_code.to_i < pub[:dr]["code"]
      out << [:warn, "Demand Response #{app_version}, published is #{pub[:dr]['version']}"]
    end
    fr_code = apps.dig(OUR_FR, "code").to_i
    if pub[:fr] && fr_code.positive? && fr_code < pub[:fr]["code"]
      out << [:warn, "Fixed Route #{fr_version}, published is #{pub[:fr]['version']}"]
    end
    out << [:warn, "Fixed Route is not installed"] if apps.any? && !apps[OUR_FR]
    per_app_setup.each do |name, st|
      out << [:warn, "#{name} can't turn WireGuard back on"] if setup["wireguard"] && st["control"] == false
    end
    out << [:warn, "WireGuard limited by battery saver"] if setup["wireguard"] && setup["wgBattery"] == false
    out << [:warn, "WireGuard remote control #{remote_control == 'off' ? 'is off' : 'not tested'}"] if setup["wireguard"] && remote_control != "on"
    per_app_setup.each do |name, st|
      out << [:warn, "#{name} can't install its updates (Install unknown apps is off)"] if st["installUpdates"] == false
    end
    out << [:warn, "Battery #{battery['percent']}%, not charging"] if battery["percent"].to_i.between?(0, 20) && !battery["charging"] && online?
    out << [:warn, "Battery health: #{battery['health']}"] if battery["health"].present? && !%w[good unknown].include?(battery["health"])
    out << [:warn, "Only #{storage['freeMB']} MB storage free"] if storage["freeMB"].present? && storage["freeMB"].to_i < 1024
    out << [:warn, "Clock is off by #{clock_skew.abs / 60} min"] if clock_skew && clock_skew.abs > 120
    per_app_setup.each do |name, st|
      out << [:warn, "#{name} has no GPS permission"] if st["location"] == false
    end
    out
  end

  # Hours the app was open per day (one report about every 10 minutes), newest last.
  def hours_by_day(days = 14)
    since = (days - 1).days.ago.beginning_of_day
    rows = pings.where("at >= ?", since)
      .group(Arel.sql("date(at at time zone 'UTC' at time zone 'America/Chicago')"))
      .pluck(Arel.sql("date(at at time zone 'UTC' at time zone 'America/Chicago')"),
             Arel.sql("count(distinct floor(extract(epoch from at) / 600))"))
      .to_h
    (0...days).map { |i| d = since.to_date + i; [d, (rows[d].to_i / 6.0).round(1)] }
  end

  # Who signed in on it lately: [[username, last time], ...]
  def recent_users(days = 30)
    pings.where("at >= ?", days.days.ago).where.not(username: nil).group(:username).maximum(:at).sort_by { |_, t| -t.to_i }
  end

  # When each app version first reported: [[version, at], ...] newest first
  def version_history
    pings.where.not(app_version: nil).group(:app_version).minimum(:at).sort_by { |_, t| -t.to_i }
  end
end
