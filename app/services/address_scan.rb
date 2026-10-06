# Nightly check for addresses and trips that will send a driver or a fare
# wrong (Philz, 2026-10-01, after seven addresses were pinned half a world
# away and a 2-mile trip measured 313 miles). Reads only; changes nothing.
#
# Finds, for every agency:
#   out_of_area  saved addresses pinned outside the service area
#   far_from_town  pinned more than FAR_MILES from where that town's other
#                addresses are (a wrong-town match: "405 East 6th Street,
#                Gonzales" 25 miles out, "Yoakum National Bank" 200)
#   no_pin       saved places, customer homes and garages with no map pin
#                (never offered by the trip form's search, so saved again)
#   trip_far     upcoming trips measured over TRIP_MILES
#   trip_pin_far addresses on trips from a week ago on, of any kind (typed,
#                coordinates only), pinned far from home: outside Texas, more
#                than FAR_MILES from their own town, or -- with no town of
#                ours -- more than HOME_MILES from every town we serve
#   duplicate    the same saved place (same name and address) more than once
#   garage_far   buses whose runs start far from their garage (GarageFit)
#   run_start_far  runs whose own start is far from their first stop (a copy
#                of the yard their bus used to live at)
#
# AddressScan.new.findings -> [Finding]; each has a stable key, so the nightly
# email (rake addresses:scan) can send only what is new since the last run.
class AddressScan
  # A mailing town here covers a lot of country (a Goliad address can be 15
  # miles out on a county road), so only a pin well beyond that is flagged:
  # the wrong-town matches this is for are 25 miles off or hundreds.
  FAR_MILES = 25
  TRIP_MILES = 100
  HOME_MILES = 60
  KEPT = %w[CustomerCommonAddress ProviderCommonAddress GarageAddress].freeze
  KINDS = {
    "out_of_area" => "Pinned outside the service area",
    "far_from_town" => "Pinned far from its own town",
    "no_pin" => "No map pin",
    "trip_far" => "Upcoming trip over #{TRIP_MILES} miles",
    "trip_pin_far" => "Trip address pinned far from home",
    "duplicate" => "Saved more than once",
    "garage_far" => "Bus garaged far from its runs",
    "run_start_far" => "Run starts far from its first stop"
  }.freeze

  Finding = Struct.new(:kind, :key, :provider_id, :label, :detail, :record_type, :record_id, keyword_init: true)

  # Where to fix a finding in RidePilot (a path; the mailer makes it a URL)
  def self.fix_path(f, routes = Rails.application.routes.url_helpers)
    case f.record_type
    when "CustomerCommonAddress"
      cid = Address.find_by(id: f.record_id).try(:customer_id)
      cid && routes.edit_customer_path(cid, locale: :en)
    when "ProviderCommonAddress" then routes.edit_provider_common_address_path(f.record_id, locale: :en)
    when "GarageAddress"
      vid = Vehicle.find_by(garage_address_id: f.record_id).try(:id)
      vid && routes.edit_vehicle_path(vid, locale: :en)
    when "Trip" then routes.edit_trip_path(f.record_id, locale: :en)
    when "Vehicle" then routes.edit_vehicle_path(f.record_id, locale: :en)
    when "Run" then routes.edit_run_path(f.record_id, locale: :en)
    end
  end

  def initialize(provider_ids = nil)
    @provider_ids = provider_ids
  end

  def findings_for_providers
    @provider_ids ? findings.select { |f| @provider_ids.include?(f.provider_id) } : findings
  end

  def findings
    @findings ||= out_of_area + far_from_town + no_pin + trips_far + trip_pins_far + duplicates + garages_far + run_starts_far
  end

  def by_kind
    list = findings_for_providers
    KINDS.keys.to_h { |k| [k, list.select { |f| f.kind == k }] }
  end

  private

  def kept
    Address.where(deleted_at: nil, type: KEPT).where("coalesce(addresses.inactive, false) = false")
  end

  def label(a)
    owner = a.is_a?(CustomerCommonAddress) ? Customer.find_by(id: a.customer_id).try(:name) : nil
    [a.name.presence, a.address, a.city].compact.join(", ") + (owner ? " (#{owner})" : "")
  end

  def finding(kind, a, detail)
    Finding.new(kind: kind, key: "#{kind}:#{a.id}", provider_id: a.provider_id || Customer.find_by(id: a.customer_id).try(:provider_id),
                label: label(a), detail: detail, record_type: a.type, record_id: a.id)
  end

  def out_of_area
    b = Address::SERVICE_AREA
    kept.where.not(the_geom: nil)
        .where("ST_X(the_geom::geometry) NOT BETWEEN ? AND ? OR ST_Y(the_geom::geometry) NOT BETWEEN ? AND ?",
               b[:min_lon], b[:max_lon], b[:min_lat], b[:max_lat])
        .map { |a| finding("out_of_area", a, "pin at #{a.latitude.round(4)}, #{a.longitude.round(4)}") }
  end

  # Each town's centre is the median of its own pinned addresses (five or
  # more), so no outside lookup is needed.
  def far_from_town
    b = Address::SERVICE_AREA
    centres = Address.connection.select_rows(<<~SQL).to_h { |c, lat, lon| [c, [lat.to_f, lon.to_f]] }
      SELECT lower(trim(city)),
             percentile_cont(0.5) WITHIN GROUP (ORDER BY ST_Y(the_geom::geometry)),
             percentile_cont(0.5) WITHIN GROUP (ORDER BY ST_X(the_geom::geometry))
      FROM addresses
      WHERE deleted_at IS NULL AND the_geom IS NOT NULL AND coalesce(trim(city), '') <> ''
        AND ST_X(the_geom::geometry) BETWEEN #{b[:min_lon]} AND #{b[:max_lon]}
        AND ST_Y(the_geom::geometry) BETWEEN #{b[:min_lat]} AND #{b[:max_lat]}
      GROUP BY 1 HAVING count(*) >= 5
    SQL
    kept.where.not(the_geom: nil).where.not(city: [nil, ""]).filter_map do |a|
      centre = centres[a.city.strip.downcase]
      next unless centre && a.latitude.between?(b[:min_lat], b[:max_lat]) && a.longitude.between?(b[:min_lon], b[:max_lon])
      miles = miles_between(centre[0], centre[1], a.latitude, a.longitude)
      finding("far_from_town", a, "#{miles.round} miles from the middle of #{a.city.strip}") if miles > FAR_MILES
    end
  end

  def no_pin
    kept.where(the_geom: nil).map { |a| finding("no_pin", a, "no pin") }
  end

  def trips_far
    Trip.where(deleted_at: nil).where("pickup_time >= ?", Time.zone.now.beginning_of_day).where("drive_distance > ?", TRIP_MILES)
        .includes(:customer).order(:pickup_time).map do |t|
      Finding.new(kind: "trip_far", key: "trip_far:#{t.id}", provider_id: t.provider_id,
                  label: "Trip #{t.id}, #{t.customer.try(:name)}, #{t.pickup_time.in_time_zone.strftime('%a %-m/%-d %-l:%M %p')}",
                  detail: "#{t.drive_distance.round} miles", record_type: "Trip", record_id: t.id)
    end
  end

  # Trip addresses the checks above don't cover (typed in a trip, or given as
  # coordinates), pinned far from home. Elvira Smith's drop-off (MATA1,
  # 2026-10-06) was typed as coordinates with the longitude's minus sign
  # missing -- a point in Asia, and a line across Louisiana on the CAD map --
  # and nothing flagged it, because only saved addresses were checked.
  def trip_pins_far
    from = 7.days.ago.beginning_of_day
    trips = Trip.where(deleted_at: nil).where("pickup_time >= ?", from)
    ids = trips.pluck(:pickup_address_id, :dropoff_address_id).flatten.compact.uniq - kept.pluck(:id)
    Address.where(id: ids).where.not(the_geom: nil).filter_map do |a|
      why = far_from_home(a) or next
      trip = trips.where("pickup_address_id = :i OR dropoff_address_id = :i", i: a.id).includes(:customer).order(:pickup_time).first
      where = a.address.present? ? a.address_text : "coordinates #{a.latitude.round(4)}, #{a.longitude.round(4)}"
      Finding.new(kind: "trip_pin_far", key: "trip_pin_far:#{a.id}", provider_id: trip&.provider_id || a.provider_id,
                  label: "#{trip&.customer&.name || 'Trip'} #{trip&.pickup_time&.in_time_zone&.strftime('%a %-m/%-d')}: #{where}",
                  detail: why, record_type: "Trip", record_id: trip&.id)
    end
  end

  # Why a pin is far from home, or nil (TownCentres: our towns' own centres)
  def far_from_home(a)
    lat, lon = a.latitude, a.longitude
    town, miles = AddressScan.nearest_served(lat, lon)
    unless lat.between?(25.8, 36.6) && lon.between?(-106.7, -93.5)
      return "pinned outside Texas, #{miles.round.to_fs(:delimited)} miles from #{town[:name]}"
    end
    own = a.city.present? && TownCentres.all[a.city.strip.downcase]
    if own
      m = TownCentres.miles(own, lat, lon)
      return m > FAR_MILES ? "#{m.round} miles from the middle of #{own[:name]}" : nil
    end
    "#{miles.round} miles from #{town[:name]}, the nearest town we serve" if miles > HOME_MILES
  end

  # The served town nearest a point, and how far: [town, miles]
  def self.nearest_served(lat, lon)
    TownCentres.all.values.select { |t| t[:n] >= TownCentres::SERVED_MIN_ADDRESSES }
               .map { |t| [t, TownCentres.miles(t, lat, lon)] }.min_by(&:last)
  end

  # Findings with a pin, for the map on the Address check page: where the pin
  # is, the nearest town we serve and how far (the page works out which way).
  MAPPED = %w[out_of_area far_from_town trip_pin_far garage_far run_start_far].freeze

  def self.pins(findings)
    findings.select { |f| MAPPED.include?(f.kind) }.filter_map do |f|
      a = case f.record_type
          when "Trip" then Address.find_by(id: f.key.split(":").last)
          when "Vehicle" then Vehicle.find_by(id: f.record_id)&.garage_address
          when "Run" then Run.find_by(id: f.record_id)&.from_garage_address
          else Address.find_by(id: f.record_id)
          end
      next unless a&.latitude
      town, miles = nearest_served(a.latitude, a.longitude)
      { kind: f.kind, label: f.label, detail: f.detail, lat: a.latitude, lon: a.longitude, fix: fix_path(f),
        town: town&.dig(:name), miles: miles&.round }
    end
  end

  # The area we serve, for framing the map: around the towns with many addresses
  def self.served_bounds
    towns = TownCentres.all.values.select { |t| t[:n] >= TownCentres::SERVED_MIN_ADDRESSES }
    return nil if towns.empty?
    [[towns.map { |t| t[:lat] }.min - 0.2, towns.map { |t| t[:lon] }.min - 0.2],
     [towns.map { |t| t[:lat] }.max + 0.2, towns.map { |t| t[:lon] }.max + 0.2]]
  end

  # The key carries the garage, so a bus moved to another wrong yard is new
  def garages_far
    GarageFit.buses.map do |b|
      g = b.garage
      Finding.new(kind: "garage_far", key: "garage_far:#{b.vehicle.id}:#{g&.id}", provider_id: b.vehicle.provider_id,
                  label: "Bus #{b.vehicle.name}: #{g ? g.address_text : 'no garage on file'}",
                  detail: b.median_miles ? "its runs start a median #{b.median_miles.round} miles away, around #{b.town} (#{b.runs} #{b.runs == 1 ? "run" : "runs"})"
                                         : "its garage has no map pin (#{b.runs} #{b.runs == 1 ? "run" : "runs"}, around #{b.town})",
                  record_type: "Vehicle", record_id: b.vehicle.id)
    end
  end

  def run_starts_far
    GarageFit.runs.map do |m|
      r = m.run
      Finding.new(kind: "run_start_far", key: "run_start_far:#{r.id}:#{m.start.id}", provider_id: r.provider_id,
                  label: "Run #{r.name} #{r.date.strftime('%a %-m/%-d')} (bus #{r.vehicle&.name}): starts at #{m.start.address_text}",
                  detail: "#{m.miles.round} miles from its first stop in #{m.first_stop.city.to_s.strip.titleize}",
                  record_type: "Run", record_id: r.id)
    end
  end

  def duplicates
    groups = ProviderCommonAddress.where(deleted_at: nil).where("coalesce(inactive, false) = false")
                                  .group_by { |a| [a.provider_id, a.address.to_s.downcase.squish, a.city.to_s.downcase.squish, a.name.to_s.downcase.squish] }
    groups.select { |(_, street, _, _), list| street.present? && list.size > 1 }.flat_map do |_, list|
      list.sort_by(&:id).drop(1).map { |a| finding("duplicate", a, "same as saved place #{list.min_by(&:id).id} (#{list.min_by(&:id).name})") }
    end
  end

  def miles_between(lat1, lon1, lat2, lon2)
    rad = ->(x) { x * Math::PI / 180 }
    a = Math.sin(rad.(lat2 - lat1) / 2)**2 + Math.cos(rad.(lat1)) * Math.cos(rad.(lat2)) * Math.sin(rad.(lon2 - lon1) / 2)**2
    2 * 3958.8 * Math.asin(Math.sqrt(a))
  end
end
