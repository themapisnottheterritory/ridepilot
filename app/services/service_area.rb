# Which area a GCRPC rider belongs to, for sorting trips on Dispatch (Kristie,
# 2026-10-02). By where the rider LIVES, so both legs of a trip sort together:
# a Calhoun rider going to a Victoria clinic is RCAL there and back.
#
#   UDR     inside Victoria city limits
#   RVIC    the rest of Victoria County      (Bloomington riders: RVIC1)
#   RCAL    Calhoun County
#   JACK    Jackson County
#   RGON    Gonzales County
#   DeWitt  DeWitt County                    (Yorktown riders: DeWitt1)
#   MATA    Matagorda County
#   OUT     a home outside those counties (note names the county when known)
#   NOPIN   a home with no map pin yet (fix the address on the rider)
#
# From the home address's pin, checked against the Census county and city
# boundaries kept in service_area_boundaries (rake service_areas:load); no address
# leaves the building. A rider on the city line can be set by hand
# (customers.service_area_override). GCRPC only: Goliad and Lavaca each run as
# their own agency with one area.
class ServiceArea
  PROVIDER_ID = 1
  COUNTY_AREA = { "Victoria" => "RVIC", "Calhoun" => "RCAL", "Jackson" => "JACK", "Gonzales" => "RGON",
                  "DeWitt" => "DeWitt", "Matagorda" => "MATA" }.freeze
  CODES = %w[UDR RVIC RCAL JACK RGON DeWitt MATA OUT NOPIN].freeze
  LABELS = { "UDR" => "UDR (Victoria city)", "RVIC" => "RVIC (rural Victoria County)", "RCAL" => "RCAL (Calhoun)",
             "JACK" => "JACK (Jackson)", "RGON" => "RGON (Gonzales)", "DeWitt" => "DeWitt", "MATA" => "MATA (Matagorda)",
             "OUT" => "Out of area", "NOPIN" => "Home not on the map" }.freeze
  # The two runs named for a town (Kristie): the town's riders go on that run.
  TOWN_RUNS = { "RVIC" => [/\Abloomington\z/i, "77951", "Bloomington (RVIC1)"],
                "DeWitt" => [/\Ayorktown\z/i, "78164", "Yorktown (DeWitt1)"] }.freeze

  Result = Struct.new(:code, :note, :source, keyword_init: true)   # source: :pin, :override, :none

  # -> Result for a customer (their override wins, else their home's pin)
  def self.for_customer(customer)
    return Result.new(code: nil, note: nil, source: :none) unless customer
    home = customer.address
    if customer.service_area_override.present?
      code = customer.service_area_override
      return Result.new(code: code, note: town_note(code, home), source: :override)
    end
    for_address(home)
  end

  def self.for_address(home)
    return Result.new(code: "NOPIN", note: nil, source: :none) unless home&.the_geom
    county, in_city = locate(home.latitude, home.longitude)
    code = if county == "Victoria" && in_city then "UDR"
           else COUNTY_AREA[county] || "OUT" end
    # out of area: name the neighbouring county when it's one we hold (Lavaca, Goliad, Wharton...)
    note = code == "OUT" ? (county && "#{county} County") : town_note(code, home)
    Result.new(code: code, note: note, source: :pin)
  end

  # [county name or nil, inside Victoria city limits?]
  def self.locate(lat, lon)
    sql = ActiveRecord::Base.sanitize_sql_array([<<~SQL, lon, lat])
      select kind, name from service_area_boundaries
      where ST_Covers(geom, ST_SetSRID(ST_MakePoint(?, ?), 4326))
    SQL
    rows = ActiveRecord::Base.connection.select_rows(sql)
    county = rows.find { |k, _| k == "county" }&.last
    [county, rows.any? { |k, n| k == "city" && n == "Victoria" }]
  end

  def self.town_note(code, home)
    town, zip, note = TOWN_RUNS[code]
    return nil unless town && home
    note if home.city.to_s.strip =~ town || home.zip.to_s.start_with?(zip)
  end

  # Tag a trip (Trip before_save); only GCRPC's.
  def self.tag(trip)
    return unless trip.provider_id == PROVIDER_ID
    r = for_customer(trip.customer)
    trip.service_area = r.code
    trip.service_area_note = r.note
  end

  # A rider's area changed (override or home): their trips from today on follow.
  def self.retag_upcoming!(customer)
    r = for_customer(customer)
    Trip.where(customer_id: customer.id, provider_id: PROVIDER_ID).where("pickup_time >= ?", Time.zone.today.beginning_of_day)
        .update_all(service_area: r.code, service_area_note: r.note)
  end

  def self.label(code)
    LABELS[code] || code
  end
end
