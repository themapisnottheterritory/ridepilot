# Fixed route (ops/fixed-route-phase1-plan.md)
#
#   rake fixed_routes:seed_lookups        — rider categories + fare types defaults,
#                                           and the Lookup Tables registration.
#   rake fixed_routes:sync[provider_id]   — routes + stops from the fixed-route
#                                           authoring tool. DRY_RUN=1 to preview.
#
# The authoring tool (~/gcrpc-fixedroute, :8080) stays the place routes are
# drawn; RidePilot is the place they are operated. Only the FY2027 city routes
# and the Inteplast commuter routes are taken; DRAFT and Retired entries are
# skipped. Re-running is safe: routes and stops are matched on their
# authoring-tool ids and updated in place, so boardings keep their stop.
require "net/http"
require "json"

namespace :fixed_routes do
  DEFAULT_RIDER_CATEGORIES = ["Adult", "Senior", "Disabled", "Student", "Child", "Transfer"].freeze
  DEFAULT_FARE_TYPES       = ["Cash", "Pass", "Free / Transfer", "No fare"].freeze

  desc "Seed rider categories and fare types (decision D1 defaults) and register the lookup tables"
  task seed_lookups: :environment do
    load Rails.root.join("db", "tasks", "seed_lookup_table_configurations.rb")
    if RiderCategory.count.zero?
      DEFAULT_RIDER_CATEGORIES.each { |n| RiderCategory.create!(name: n) }
      puts "rider categories: #{DEFAULT_RIDER_CATEGORIES.join(', ')}"
    else
      puts "rider categories already present (#{RiderCategory.count}), left alone"
    end
    if FareType.count.zero?
      DEFAULT_FARE_TYPES.each { |n| FareType.create!(name: n) }
      puts "fare types: #{DEFAULT_FARE_TYPES.join(', ')}"
    else
      puts "fare types already present (#{FareType.count}), left alone"
    end
    puts "lookup tables registered: #{LookupTable.where(name: %w[rider_categories fare_types]).pluck(:caption).join(' / ')}"
  end

  desc "Sync routes and stops from the fixed-route authoring tool (DRY_RUN=1 to preview)"
  task :sync, [:provider_id] => :environment do |_t, args|
    provider = Provider.find(args[:provider_id] || 1)
    base     = (ENV["FIXED_ROUTE_AUTHORING_URL"].presence || "http://10.0.0.16:8080").chomp("/")
    dry      = ENV["DRY_RUN"].to_s == "1"
    puts "authoring tool: #{base}  provider: #{provider.name}#{dry ? '  (DRY RUN)' : ''}"

    list = fetch_json("#{base}/api/routes")
    wanted = list.select { |r| syncable_route?(r) }
    puts "routes listed: #{list.size}, syncable: #{wanted.size} (#{list.size - wanted.size} DRAFT/Retired/other skipped)"

    grouped = Hash.new { |h, k| h[k] = [] }
    wanted.each do |r|
      detail = fetch_json("#{base}/api/routes/#{r['route_id']}")
      grouped[route_key(detail)] << detail
    end

    seen_names = []
    stats = { routes_created: 0, routes_updated: 0, stops_upserted: 0, stops_removed: 0 }
    grouped.each do |(name, kind), details|
      seen_names << name
      details = details.sort_by { |d| d["route_id"] }
      color   = details.map { |d| d.dig("gtfs", "route_color").presence }.compact.first || (kind == "commuter" ? "4A4A4A" : nil)
      short   = details.map { |d| d["short_name"].presence }.compact.first
      ids     = details.map { |d| d["route_id"] }
      route   = FixedRoute.for_provider(provider.id).find_by(name: name)
      action  = route ? "update" : "create"
      puts format("  %-7s %-12s %-9s color=%-7s %s", action, name, kind, color || "-", ids.join(", "))
      next if dry
      route ||= FixedRoute.new(provider: provider, name: name)
      route.assign_attributes(kind: kind, color: color, short_name: short, external_route_ids: ids, active: true)
      route.save!
      stats[action == "create" ? :routes_created : :routes_updated] += 1

      details.each do |d|
        direction = direction_for(d)
        keep_ids = []
        d["stops"].each_with_index do |s, i|
          lng, lat = s["position"]
          stop = route.stops.find_or_initialize_by(external_route_id: d["route_id"], external_stop_id: s["stop_id"])
          stop.assign_attributes(direction: direction, sequence: i, name: s["name"], latitude: lat, longitude: lng,
                                 timepoint: !!s["is_timepoint"], distance_along_shape_m: s["distance_along_shape_m"])
          stop.save!
          keep_ids << stop.id
          stats[:stops_upserted] += 1
        end
        gone = route.stops.where(external_route_id: d["route_id"]).where.not(id: keep_ids)
        stats[:stops_removed] += gone.count
        gone.destroy_all
        puts format("          %-6s %2d stops", direction, d["stops"].size)
      end
    end

    # Routes that came from the tool before but are no longer offered: keep
    # them (history), just switch them off.
    stale = FixedRoute.for_provider(provider.id).active.where.not(name: seen_names).where("cardinality(external_route_ids) > 0")
    stale.each { |r| puts "  retire  #{r.name} (no longer in the authoring tool)" }
    stale.update_all(active: false) unless dry

    puts dry ? "dry run, nothing written" : "done: #{stats.map { |k, v| "#{k}=#{v}" }.join(' ')}"
  end

  desc "Create one repeating run per fixed-route block (unassigned; dispatch adds driver + vehicle). DRY_RUN=1 to preview"
  task :seed_repeating_runs, [:provider_id] => :environment do |_t, args|
    # Decision D2 default: one block per city route per service day spanning the
    # timetable (first departure - 30 min to last arrival + 30 min); the Inteplast
    # commuters get an AM and a PM block. Spans and service days come from the
    # authoring tool's timetable, so this reads the tool like `sync` does.
    provider = Provider.find(args[:provider_id] || 1)
    base     = (ENV["FIXED_ROUTE_AUTHORING_URL"].presence || "http://10.0.0.16:8080").chomp("/")
    dry      = ENV["DRY_RUN"].to_s == "1"
    pad      = (ENV["BLOCK_PAD_MINUTES"] || 30).to_i
    puts "provider: #{provider.name}#{dry ? '  (DRY RUN)' : ''}  pad: #{pad} min"
    created = 0; kept = 0

    FixedRoute.for_provider(provider.id).active.default_order.each do |route|
      details = route.external_route_ids.map { |id| fetch_json("#{base}/api/routes/#{id}") }
      days = details.flat_map { |d| d["runs"].flat_map { |r| r["service_days"] } }.uniq
      blocks = if route.commuter?
        # each direction detail lists an AM and a PM run; take the earliest first-stop and latest last-stop per half of the day
        ams = []; pms = []
        details.each do |d|
          st = d["stops"]; next if st.empty?
          d["runs"].each do |r|
            first = st.first.dig("scheduled_times_by_run", r["run_id"]); last = st.last.dig("scheduled_times_by_run", r["run_id"])
            next unless first && last
            (first < "12:00" ? ams : pms) << [first, last]
          end
        end
        [["AM", ams], ["PM", pms]].select { |_, l| l.any? }.map { |label, l| [label, l.map(&:first).min, l.map(&:last).max] }
      else
        times = details.flat_map { |d| st = d["stops"]; d["runs"].map { |r| [st.first.dig("scheduled_times_by_run", r["run_id"]), st.last.dig("scheduled_times_by_run", r["run_id"])] } }.reject { |a, b| a.nil? || b.nil? }
        times.any? ? [[nil, times.map(&:first).min, times.map(&:last).max]] : []
      end

      blocks.each do |label, first, last|
        name  = [route.name, label].compact.join(" ")
        start = block_time(first, -pad); finish = block_time(last, pad)
        existing = RepeatingRun.where(provider_id: provider.id, name: name).first
        puts format("  %-7s %-14s %s-%s  %s", existing ? "keep" : "create", name, start, finish, days.map { |d| d[0..1].capitalize }.join(""))
        if existing then kept += 1; next end
        next if dry
        rr = RepeatingRun.new(name: name, provider: provider, service_mode: "fixed_route", fixed_route: route, paid: true,
                              scheduled_start_time: Time.zone.parse(start), scheduled_end_time: Time.zone.parse(finish),
                              start_date: Date.today, repetition_interval: 1)
        %w[monday tuesday wednesday thursday friday saturday sunday].each { |d| rr.send("repeats_#{d}s=", days.include?(d[0, 3])) }
        rr.save!
        created += 1
      end
    end
    puts dry ? "dry run, nothing written" : "done: created=#{created} kept=#{kept}. Assign drivers and vehicles on Runs > Repeating Runs; tonight's scheduler generates the daily runs."
  end

  # ---- helpers -------------------------------------------------------------

  def fetch_json(url)
    res = Net::HTTP.get_response(URI(url))
    raise "#{url} → HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)
    JSON.parse(res.body)
  end

  def syncable_route?(r)
    id = r["route_id"].to_s
    name = r["name"].to_s
    return false if name =~ /\bDRAFT\b/i || name =~ /\bRetired\b/i
    id.start_with?("fy2027-") || id.end_with?("-inteplast")
  end

  # "fy2027-red-east" → ["Red", "city"]; "bay-inteplast" → ["Bay", "commuter"]
  def route_key(detail)
    id = detail["route_id"]
    if id.start_with?("fy2027-")
      [id.split("-")[1].capitalize, "city"]
    else
      [(detail["short_name"].presence || id.sub("-inteplast", "").split("-").map(&:capitalize).join(" ")), "commuter"]
    end
  end

  # "08:17:20" + offset minutes, rounded to 5 min → "07:45"
  def block_time(hhmmss, offset_min)
    h, m = hhmmss.split(":").first(2).map(&:to_i)
    total = (h * 60 + m + offset_min).clamp(0, 23 * 60 + 55)
    total = (total / 5.0).round * 5
    format("%02d:%02d", total / 60, total % 60)
  end

  def direction_for(detail)
    id = detail["route_id"]
    if id.start_with?("fy2027-")
      id.split("-").last.capitalize                 # East / West / North / South
    else
      "Round trip"                                  # out to Inteplast and back in one trip
    end
  end
end
