# Dispatch's operator schedule, brought into RidePilot's daily runs.
#
# The schedule is "Operator Schedule (FY26).xlsx" on the Transportation
# Operations SharePoint site, kept by dispatch. The schedule bot on 10.0.0.18
# parses it live and serves a per-day roster over HTTP:
#
#   GET <url>/roster?date=<ISO|today|tomorrow>&category=fixed,commuter
#   Authorization: Bearer <token>
#
# Each roster entry is one route and shift ("GOLD (AM)") with an operator and a
# status of assigned, open (nobody yet) or not_in_service. A one-bus day is
# written by dispatch as the same operator on two routes; the roster reports
# those under `combos`.
#
# This class compares that with the day's fixed-route runs here and, in apply
# mode, puts the roster's driver on each run. It never clears a driver and
# never touches a run that has started: dispatch's sheet is the plan, the run
# is what happened. Until the dispatch team schedules in RidePilot directly
# this is how the tablet's pull-out gets its "Scheduled" pin without Kristie
# retyping the sheet each morning.
#
#   rake fixed_routes:roster[tomorrow,watch]     # report only
#   rake fixed_routes:roster[tomorrow,apply]     # assign drivers
require "net/http"
require "json"

class RosterSync
  class Error < StandardError; end

  # Roster spellings that are not simply the RidePilot name capitalised.
  ROUTE_ALIASES = {
    "PORT LAVACA" => "Port Lavaca", "PL" => "Port Lavaca", "PORTLAVACA" => "Port Lavaca",
    "VIC 1" => "Vic1", "VIC 2" => "Vic2", "VICTORIA 1" => "Vic1", "VICTORIA 2" => "Vic2",
    "EL CAMPO" => "Campo", "PALACIOS" => "Pal", "BAY CITY" => "Bay",
    # VIC3 was a commuter route of its own; short of drivers it is folded into
    # the Edna bus, and the sheet names that slot "VIC3/EDNA". When drivers
    # return and VIC3 runs alone again it needs its own route here and in the
    # authoring tool, and this alias goes.
    "VIC3/EDNA" => "Edna", "VIC 3/EDNA" => "Edna", "EDNA/VIC3" => "Edna",
  }.freeze

  # "BAY CITY ASSIST", "EDNA ASSIST": an overflow bus that follows the route
  # and picks up whoever did not fit. A second driver and bus, but not a route
  # of its own and no RidePilot run: reported, never matched, never alerted.
  ASSIST = /\bASSIST\b/i

  # On a one-bus day the driver sits on one RidePilot run and the partner runs
  # stay empty. Two shapes of that:
  #
  # A city block: the bus drives one route's loop then the other's, and the
  # tablet flips between them on one run. The run is the route driven first --
  # Gold then Green (gcrpc-fixedroute/ops/one-bus-combo.md).
  BLOCK_LEAD = { "Green" => "Gold" }.freeze
  #
  # A commuter double: one interleaved trip through both routes' pickups, which
  # is a route of its own in the authoring tool and in RidePilot (ops/
  # make-tandem-routes.py). The sheet still lists the two single routes with
  # the same operator; the run that gets the driver is the tandem's.
  TANDEM = { %w[Bay Pal] => "Bay+Pal", ["Port Lavaca", "Vic2"] => "Port Lavaca+Vic2", %w[Edna Vic1] => "Vic1+Edna" }.freeze

  Row = Struct.new(:category, :route, :shift, :fixed_route, :run, :roster_driver, :driver, :current_driver,
                   :status, :action, :note, keyword_init: true)

  attr_reader :provider, :url, :token

  def initialize(provider:, url:, token:, http: nil)
    @provider = provider
    @url = url.to_s.chomp("/")
    @token = token
    @http = http   # injectable for tests: ->(uri, headers) { [code, body] }
  end

  # ---- fetch -------------------------------------------------------------------

  def fetch(date, categories)
    uri = URI("#{url}/roster?date=#{date}&category=#{Array(categories).join(',')}")
    code, body = (@http || method(:get)).call(uri, { "Authorization" => "Bearer #{token}" })
    raise Error, "roster: HTTP #{code} from #{uri.host}: #{body.to_s[0, 200]}" unless code.to_i == 200
    json = JSON.parse(body)
    raise Error, "roster: #{json['error']} (#{json['message'] || date})" if json["error"]
    json
  rescue JSON::ParserError => e
    raise Error, "roster: not JSON (#{e.message})"
  end

  # ---- plan ----------------------------------------------------------------------

  # What the roster says against what RidePilot has, one row per route. Nothing
  # is written.
  def plan(roster)
    date = Date.parse(roster["date"])
    rows = []
    combos = combos_of(roster)
    (roster["categories"] || {}).each do |category, entries|
      by_route = entries.group_by { |e| e["route"].to_s.strip.upcase }
      by_route.each do |roster_route, shifts|
        fixed_route = find_route(roster_route)
        # A route with an AM and a PM run here (the commuters) is planned per
        # shift from the sheet's own AM and PM columns; a route with one run a
        # day (the city loops) takes the day's operator.
        runs = fixed_route ? runs_for(fixed_route, date) : []
        slots = runs.size >= 2 ? shifts.group_by { |e| e["shift"].to_s.strip.upcase.presence || "AM" } : { nil => shifts }
        slots.each do |shift, slot_entries|
          row = Row.new(category: category, route: roster_route, shift: shift, fixed_route: fixed_route, note: [])
          statuses = slot_entries.map { |e| e["status"].to_s }
          operators = slot_entries.map { |e| e["operator"].to_s.strip }.reject(&:blank?).uniq

          if roster_route =~ ASSIST
            row.status = :assist
            row.action = :assist
            row.roster_driver = operators.first
            row.note << (operators.any? ? "overflow bus: #{operators.join(' / ')}" : "overflow bus, nobody on it")
            rows << row
            next
          end
          if fixed_route.nil?
            row.action = :unknown_route
            row.note << "no RidePilot route named like #{roster_route.inspect}"
            rows << row
            next
          end
          row.run = pick_run(runs, shift)
          row.current_driver = row.run&.driver

          if statuses.all? { |st| st == "not_in_service" }
            row.status = :not_in_service
            row.action = :skip
            row.note << "RidePilot has #{row.current_driver.user_name} on a route the sheet says is not in service" if row.current_driver
            rows << row
            next
          end
          if operators.empty?
            row.status = :open
            row.action = row.current_driver ? :keep : :open
            row.note << (row.current_driver ? "sheet is open; RidePilot already has #{row.current_driver.user_name} (kept)" : "no driver on the sheet")
            rows << row
            next
          end

          row.status = :assigned
          row.roster_driver = operators.first
          row.note << "AM and PM differ on the sheet (#{operators.join(' / ')}); using #{operators.first}" if operators.size > 1 && shift.nil?

          combo = combos[row.roster_driver.upcase]
          if combo && combo.size > 1
            lead = lead_route(combo)
            if lead != fixed_route.name
              row.action = :combo_partner
              row.note << "one-bus day: #{row.roster_driver} drives #{combo.join(' + ')}; the run is #{lead}'s, this one stays empty"
              row.note << "RidePilot has #{row.current_driver.user_name} here — two drivers for one bus?" if row.current_driver
              rows << row
              next
            end
            row.note << "one-bus day: #{row.roster_driver} drives #{combo.join(' + ')}"
          end
          rows << assign(row, date)
        end
      end

      # A commuter double's run belongs to a route the sheet never names. For
      # each shift where the pair's rows both wait on the same operator, add
      # the tandem's row with that operator.
      combos.each do |_op, routes|
        lead = lead_route(routes)
        next if routes.include?(lead) || rows.any? { |r| r.fixed_route&.name == lead }
        partners = rows.select { |r| r.category == category && r.fixed_route && routes.include?(r.fixed_route.name) }
        next if partners.empty?
        tandem = find_route(lead)
        tandem_runs = tandem ? runs_for(tandem, date) : []
        partners.group_by(&:shift).each do |shift, group|
          waiting = group.select { |r| r.action == :combo_partner }
          next unless waiting.size == group.size && waiting.map(&:roster_driver).uniq.size == 1
          op = waiting.first.roster_driver
          row = Row.new(category: category, route: lead.upcase, shift: shift, fixed_route: tandem,
                        note: ["one bus: #{op} drives #{routes.join(' + ')} as #{lead}"])
          if tandem.nil?
            row.action = :unknown_route
            row.note << "no RidePilot route named #{lead.inspect} for the double"
            rows << row
            next
          end
          row.run = pick_run(tandem_runs, shift)
          row.current_driver = row.run&.driver
          row.status = :assigned
          row.roster_driver = op
          rows << assign(row, date)
        end
      end
    end
    rows
  end

  # The driver for an :assigned row: matched, compared with the run, decided.
  def assign(row, date)
    row.driver = find_driver(row.roster_driver)
    if row.run.nil?
      row.action = :no_run
      row.note << "no RidePilot run for #{row.fixed_route.name} on #{date}"
    elsif row.driver.nil?
      row.action = :unknown_driver
      row.note << "no RidePilot driver matching #{row.roster_driver.inspect}"
    elsif row.run.actual_start_time.present?
      row.action = :started
      row.note << "run already started (#{row.current_driver&.user_name || 'no driver'}), left alone"
    elsif row.current_driver == row.driver
      row.action = :same
    elsif row.current_driver
      row.action = :assign
      row.note << "RidePilot has #{row.current_driver.user_name}, sheet says #{row.driver.user_name}"
    else
      row.action = :assign
    end
    row
  end

  def runs_for(fixed_route, date)
    Run.where(provider_id: provider.id, date: date, service_mode: "fixed_route",
              fixed_route_id: fixed_route.id, deleted_at: nil).order(:scheduled_start_time, :id).to_a
  end

  # The run for a shift: with two runs a day, AM is the one starting before
  # noon; with one, it is that one whatever the shift.
  def pick_run(runs, shift)
    return runs.first if runs.size < 2 || shift.nil?
    am = runs.select { |r| r.scheduled_start_time.nil? || r.scheduled_start_time.hour < 12 }
    (shift == "PM" ? (runs - am) : am).first || runs.first
  end

  # ---- apply ---------------------------------------------------------------------

  # Put the roster's driver on every :assign run. Returns the rows it changed;
  # a run that refuses (driver already on an overlapping run, say) keeps its
  # note and is not changed.
  def apply!(rows)
    changed = []
    PaperTrail.request(whodunnit: "roster-sync") do
      rows.select { |r| r.action == :assign }.each do |r|
        if r.run.update(driver: r.driver)
          changed << r
        else
          r.action = :refused
          r.note << "RidePilot refused: #{r.run.errors.full_messages.to_sentence}"
        end
      end
    end
    changed
  end

  # ---- report ---------------------------------------------------------------------

  FLAG = { unknown_route: "!!", unknown_driver: "!!", no_run: "!!", refused: "!!", open: "!!",
           assign: "->", combo_partner: "..", started: "..", keep: "..", skip: "  ", same: "  ", assist: "  " }.freeze

  def report(roster, rows, mode:)
    lines = []
    lines << "Roster for #{roster['date']} (#{roster['weekday']}), #{mode} mode, generated #{roster['generated_at']}"
    rows.group_by(&:category).each do |category, group|
      lines << "  [#{category}]"
      group.sort_by { |r| [r.fixed_route&.name || r.route, r.shift.to_s] }.each do |r|
        who = case r.action
              when :same, :started then r.current_driver&.user_name
              when :assign then r.driver.user_name
              when :combo_partner then "(empty)"
              when :skip then "not in service"
              when :open then "OPEN"
              when :assist then r.roster_driver || "(nobody)"
              when :keep then r.current_driver&.user_name
              else r.roster_driver
              end
        label = [(r.fixed_route&.name || r.route), r.shift].compact.join(" ")
        lines << format("  %s %-19s %-22s %-14s %s", FLAG.fetch(r.action, "??"), label,
                        who.to_s, r.action, r.note.join("; "))
      end
    end
    combos = combos_of(roster)
    lines << "  one-bus days: " + combos.map { |op, routes| "#{op.titleize} on #{routes.join(' + ')}" }.join("; ") if combos.any?
    counts = rows.group_by(&:action).transform_values(&:size).sort_by { |k, _| k.to_s }.map { |k, v| "#{k}=#{v}" }.join(" ")
    lines << "  #{counts}"
    lines.join("\n")
  end

  # Rows that deserve a human's eye (the alerts file).
  def alerts(rows)
    rows.select { |r| FLAG[r.action] == "!!" }
  end

  private

  def get(uri, headers)
    req = Net::HTTP::Get.new(uri)
    headers.each { |k, v| req[k] = v }
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 30) { |h| h.request(req) }
    [res.code, res.body]
  end

  # { "MARY RAMOS" => ["Gold", "Green"] } from the roster's combos, in RidePilot names.
  def combos_of(roster)
    out = {}
    (roster["combos"] || {}).each_value do |list|
      Array(list).each do |c|
        op = (c["operator"] || c["name"]).to_s.strip.upcase
        routes = Array(c["routes"]).reject { |r| r.to_s =~ ASSIST }.map { |r| find_route(r.to_s)&.name || r.to_s }
        out[op] = ((out[op] || []) + routes).uniq if op.present?
      end
    end
    out
  end

  # The run goes on: the tandem route for a commuter double; else a route
  # RidePilot knows -- the block's lead if one is defined, else the first
  # alphabetically.
  def lead_route(routes)
    tandem = TANDEM[routes.sort]
    return tandem if tandem
    known = routes.select { |r| find_route(r) }
    pool = known.any? ? known : routes
    leads = pool.map { |r| BLOCK_LEAD[r] }.compact
    (leads & pool).first || pool.sort.first
  end

  def find_route(roster_name)
    key = roster_name.to_s.strip.upcase.sub(/\s*\([^)]*\)\s*\z/, "")   # "EDNA ASSIST (AM/PM)" → "EDNA ASSIST"
    name = ROUTE_ALIASES[key] || key.capitalize
    @routes ||= FixedRoute.for_provider(provider.id).active.to_a
    @routes.find { |r| r.name.casecmp?(name) } || @routes.find { |r| r.name.casecmp?(key) }
  end

  # "Ram Mejia" matches Ramiro Mejia: same last name, one first name a prefix
  # of the other. Two candidates is no match: better an alert than a guess.
  def find_driver(operator)
    @drivers ||= Driver.for_provider(provider.id).where(active: true).includes(:user).to_a.select(&:user)
    first, last = split_name(operator)
    return nil if last.blank?
    exact = @drivers.select { |d| d.user.last_name.to_s.casecmp?(last) && d.user.first_name.to_s.casecmp?(first) }
    return exact.first if exact.size == 1
    loose = @drivers.select do |d|
      d.user.last_name.to_s.casecmp?(last) &&
        (d.user.first_name.to_s.downcase.start_with?(first.downcase) || first.downcase.start_with?(d.user.first_name.to_s.downcase))
    end
    loose.size == 1 ? loose.first : nil
  end

  def split_name(s)
    parts = s.to_s.strip.split(/\s+/)
    return [parts[0].to_s, ""] if parts.size < 2
    [parts[0], parts[1..].join(" ")]
  end
end
