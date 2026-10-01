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
#   duplicate    the same saved place (same name and address) more than once
#
# AddressScan.new.findings -> [Finding]; each has a stable key, so the nightly
# email (rake addresses:scan) can send only what is new since the last run.
class AddressScan
  # A mailing town here covers a lot of country (a Goliad address can be 15
  # miles out on a county road), so only a pin well beyond that is flagged:
  # the wrong-town matches this is for are 25 miles off or hundreds.
  FAR_MILES = 25
  TRIP_MILES = 100
  KEPT = %w[CustomerCommonAddress ProviderCommonAddress GarageAddress].freeze
  KINDS = {
    "out_of_area" => "Pinned outside the service area",
    "far_from_town" => "Pinned far from its own town",
    "no_pin" => "No map pin",
    "trip_far" => "Upcoming trip over #{TRIP_MILES} miles",
    "duplicate" => "Saved more than once"
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
    end
  end

  def initialize(provider_ids = nil)
    @provider_ids = provider_ids
  end

  def findings_for_providers
    @provider_ids ? findings.select { |f| @provider_ids.include?(f.provider_id) } : findings
  end

  def findings
    @findings ||= out_of_area + far_from_town + no_pin + trips_far + duplicates
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
