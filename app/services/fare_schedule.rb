# Prices a demand-response trip from the provider's fare tables
# (docs/fare-card-design.md, section 15; county tables since 2026-09-28).
#
#   FareSchedule.new(provider).price(miles: 7.2, category: senior)   # => 1.00, or nil if no table
#   FareSchedule.new(provider).trip_fare(trip)                        # rider + guests, attendants free
#   FareSchedule.new(provider).quote(trip)                            # the same, with how it was priced
#
# Since the FY27 fare structure every area, the Goliad and Lavaca tenants
# included, uses one distance table: the provider's default (county ''). A
# county can still have its own table, chosen by the rider's county (home
# address, else the pickup), and a table can end on a date, compared with
# the trip's date (Gonzales rides free through 2026-09-30). A county with
# zone rows prices by where the trip goes; none do today.
#
# The rider pays their category's fare for the trip's band. A companion or
# guest pays the same fare as the rider (FY27: "the same fare charged to the
# fixed route, rural disabled and complementary paratransit rider").
# Attendants (personal care assistants) ride free. Returns nil when the trip cannot be priced --
# no table, no distance, no cell for the rider's category, or a destination
# the county's zones do not cover -- so callers show nothing rather than a
# wrong number, or fall through to the flat default.
class FareSchedule
  # Counties GCRPC serves; a trip ending in one of these (other than the
  # rider's own) is an "other servicing county" trip for the zone counties.
  SERVICE_COUNTIES = %w[Calhoun DeWitt Goliad Gonzales Jackson Lavaca Matagorda Victoria].freeze

  # amount: rider plus the trip's guests. rider / guest_each: the parts, for
  # quoting a trip whose guests are not counted yet. category_source: where
  # the rider's category came from (see #rider_category).
  Quote = Struct.new(:amount, :rider, :guest_each, :guests, :category, :category_assumed, :category_source,
                     :county, :basis, :miles, :no_fare, keyword_init: true)

  attr_reader :provider, :service, :county

  def initialize(provider, service: "demand_response", county: "")
    @provider = provider
    @service = service
    @county = county.to_s.strip
  end

  # This table's cells (the county given, or the default table).
  def rows
    @rows ||= FareScheduleRow.for_provider(provider.id).for_service(service).for_county(county).includes(:rider_category).by_band.to_a
  end

  def configured?
    rows.any?
  end

  # The last day this table applies (nil: no end).
  def ends_on
    rows.first&.ends_on
  end

  def in_effect_on?(date)
    configured? && (ends_on.nil? || date.nil? || date <= ends_on)
  end

  def bands
    rows.map(&:up_to_miles).uniq
  end

  def price(miles:, category:)
    return nil unless configured? && category
    m = BigDecimal(miles.to_s)
    band = bands.find { |edge| edge.nil? || m <= edge }
    row = rows.find { |r| r.up_to_miles == band && r.rider_category_id == category.id }
    row&.fare
  end

  # The whole fare for a trip: rider plus guests, attendants free. nil if it
  # cannot be priced.
  def trip_fare(trip, category: nil)
    quote(trip, category: category)&.amount
  end

  # The fare and how it was reached, for the office to read out. Paratransit
  # comes first: an ADA-eligible rider on a trip inside the urban service
  # area pays the flat paratransit fare (and so does each companion)
  # whatever the distance.
  def quote(trip, category: nil)
    category, source = category ? [category, :given] : rider_category(trip)
    base = { category: category, category_assumed: source == :assumed, category_source: source,
             miles: trip.drive_distance.presence&.to_f }
    guests = trip.guest_count.to_i

    if paratransit?(trip)
      flat = provider.fare_paratransit.to_d
      return Quote.new(**base, amount: (flat * (1 + guests)).round(2), rider: flat, guest_each: flat, guests: guests,
                       county: nil, basis: "ADA paratransit, #{urban_cities.map(&:titleize).join(' / ')}")
    end

    home = rider_county(trip)
    zones = zone_rows(home)
    if zones.any?
      zone, place = zone_for(trip, home, zones)
      return nil unless zone
      rider = zone_price(zones, zone, place, category)
      return nil if rider.nil?
      guest_fare = rider                                   # companions pay the rider's fare
      name = zones.first.county
      return Quote.new(**base, amount: (rider + guest_fare * guests).round(2), rider: rider, guest_each: guest_fare, guests: guests,
                       county: name, basis: zone_label(name, zone, place))
    end

    table = table_for(home, trip_date(trip))
    return nil unless table.configured? && trip.drive_distance.to_f > 0
    rider = table.price(miles: trip.drive_distance, category: category)
    return nil if rider.nil?
    guest_fare = rider                                     # companions pay the rider's fare
    name = table.rows.first.county.presence     # the table's own spelling, not the address's
    label = name ? "#{name} County fare" : "standard fare"
    label += " through #{table.ends_on.strftime('%-m/%-d')}" if name && table.ends_on
    Quote.new(**base, amount: (rider + guest_fare * guests).round(2), rider: rider, guest_each: guest_fare, guests: guests,
              county: name,
              basis: "#{label}, #{format('%.1f', trip.drive_distance.to_f)} mi")
  end

  # ADA-eligible rider, both ends of the trip in one of the provider's urban
  # cities, and a paratransit fare set.
  def paratransit?(trip)
    return false unless provider.fare_paratransit.to_f > 0
    return false unless trip.customer&.ada_eligible
    urban_trip?(trip)
  end

  def urban_trip?(trip)
    cities = urban_cities
    return false if cities.empty?
    [trip.pickup_address, trip.dropoff_address].all? { |a| a && cities.include?(a.city.to_s.strip.downcase) }
  end

  def urban_cities
    provider.fare_urban_cities.to_s.split(",").map { |c| c.strip.downcase }.reject(&:blank?)
  end

  # The category on the customer record, else Senior for a rider marked
  # elderly, else the first category (Adult).
  def category_for(customer)
    rider_category_on_file(customer) || (customer&.is_elderly && senior_category) || categories.first
  end

  # [category, source] for the rider on this trip. The customer's Fare
  # category wins; without one, the trip's passenger tracking counts
  # (disabled / senior passengers served, which staff fill in per trip for
  # the 5310 report) say the rider is Disabled or Senior; then the customer's
  # elderly box; then Adult, assumed.
  def rider_category(trip)
    customer = trip.customer
    if (c = rider_category_on_file(customer)) then return [c, :customer] end
    if trip.try(:number_of_disabled_passengers_served).to_i > 0 && disabled_category then return [disabled_category, :trip_tracking] end
    if trip.try(:number_of_senior_passengers_served).to_i > 0 && senior_category then return [senior_category, :trip_tracking] end
    if customer&.is_elderly && senior_category then return [senior_category, :elderly_flag] end
    [categories.first, :assumed]
  end

  def senior_category
    categories.find { |c| c.name.to_s.downcase.start_with?("senior") }
  end

  def disabled_category
    categories.find { |c| c.name.to_s.downcase.start_with?("disab") }
  end


  # The provider's rider categories in display order, loaded once.
  def categories
    @categories ||= RiderCategory.by_provider(provider).default_order.to_a
  end

  # The rider's county: home address, else where the trip starts.
  def rider_county(trip)
    [trip.customer&.address&.county, trip.pickup_address&.county].map { |c| c.to_s.strip }.find(&:present?)
  end

  # The distance table for a county on a date: its own if it has one in
  # effect then, else the default.
  def table_for(county_name, date = nil)
    if county_name.present?
      @tables ||= {}
      own = (@tables[county_name.downcase] ||= self.class.new(provider, service: service, county: county_name))
      return own if own.in_effect_on?(date)
    end
    county.blank? ? self : (@default_table ||= self.class.new(provider, service: service))
  end

  # The day the trip runs, in local time.
  def trip_date(trip)
    trip.pickup_time&.in_time_zone&.to_date || trip.try(:date) || Date.current
  end

  # Replace this table (the county given, or the default) from a grid of
  # { up_to_miles => { rider_category_id => fare } }. A blank edge is the
  # open-ended band. Blank cells are $0.00 (free).
  def replace!(grid, by: nil, ends_on: nil)
    FareScheduleRow.transaction do
      PaperTrail.request(whodunnit: by&.id.to_s.presence) do
        FareScheduleRow.for_provider(provider.id).for_service(service).for_county(county).destroy_all
        grid.each do |edge, cells|
          edge_val = edge.to_s.strip.presence && BigDecimal(edge.to_s)
          cells.each do |category_id, fare|
            FareScheduleRow.create!(provider: provider, service: service, county: county, up_to_miles: edge_val, ends_on: ends_on,
                                    rider_category_id: category_id, fare: (BigDecimal(fare.to_s.gsub(/[$,\s]/, "")) rescue 0))
          end
        end
      end
    end
    @rows = nil
    self
  end

  private

  def rider_category_on_file(customer)
    return nil unless customer&.default_rider_category_id
    categories.find { |c| c.id == customer.default_rider_category_id }
  end

  def zone_rows(county_name)
    return [] if county_name.blank?
    @zone_rows ||= {}
    @zone_rows[county_name.downcase] ||= FareZoneRow.for_provider(provider.id).for_county(county_name).to_a
  end

  def norm(s)
    s.to_s.strip.downcase
  end

  # [zone, place] for a trip, or nil when the zones do not cover it. Both ends
  # at home: a town zone if both are in the same listed town, else the
  # county. Otherwise the far end decides: a named city, else another
  # service county.
  def zone_for(trip, home, zones)
    ends = [trip.pickup_address, trip.dropoff_address]
    return nil if ends.any?(&:nil?)
    at_home = ->(a) { norm(a.county) == norm(home) }
    if ends.all?(&at_home)
      town = zones.select { |z| z.zone == "town" }.map(&:place).uniq.find { |p| ends.all? { |a| norm(a.city) == norm(p) } }
      return town ? ["town", town] : ["county", nil]
    end
    away = at_home.call(trip.dropoff_address) ? trip.pickup_address : trip.dropoff_address
    city = zones.select { |z| z.zone == "city" }.map(&:place).uniq.find { |p| norm(away.city) == norm(p) }
    return ["city", city] if city
    return ["other_county", nil] if SERVICE_COUNTIES.map(&:downcase).include?(norm(away.county))
    nil
  end

  def zone_price(zones, zone, place, category)
    return nil unless category
    zones.find { |z| z.zone == zone && norm(z.place) == norm(place) && z.rider_category_id == category.id }&.fare
  end

  def zone_label(home, zone, place)
    case zone
    when "town"         then "#{home} County fare, within #{place}"
    when "county"       then "#{home} County fare, within the county"
    when "other_county" then "#{home} County fare, to another county"
    when "city"         then "#{home} County fare, to #{place}"
    end
  end
end
