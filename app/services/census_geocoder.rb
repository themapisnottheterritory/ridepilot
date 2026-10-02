require "net/http"

# The US Census Bureau's address lookup (geocoding.geo.census.gov): street
# address -> map point and county. Free, no account. Our own map search
# (Nominatim on OpenStreetMap) knows the towns but not many rural house
# numbers, so a saved place typed by hand used to land with no pin and never
# come up when booking (Philz 2026-10-02: "DaVita El Campo Dialysis, 307
# Sandy Corner Rd" saved three times, Not on map each time).
#
# Only saved places (ProviderCommonAddress) are looked up -- facility
# addresses, never riders' homes or names: a saved place named like a home, or
# on the same street address as a rider's home, is skipped. Only an exact,
# single match is used; anything ambiguous is left for a person.
class CensusGeocoder
  URL = "https://geocoding.geo.census.gov/geocoder/geographies/onelineaddress".freeze
  NIGHTLY_LIMIT = 50

  Result = Struct.new(:lat, :lon, :county, :matched, keyword_init: true)

  # -> Result or nil
  def self.lookup(street:, city: nil, state: "TX", zip: nil)
    line = [street, city, [state.presence || "TX", zip].compact.join(" ")].map(&:to_s).map(&:strip).reject(&:blank?).join(", ")
    return nil if street.to_s.strip.length < 5
    uri = URI(URL)
    uri.query = URI.encode_www_form(address: line, benchmark: "Public_AR_Current", vintage: "Current_Current",
                                    layers: "Counties", format: "json")
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |h| h.get(uri.request_uri) }
    return nil unless res.is_a?(Net::HTTPSuccess)
    matches = JSON.parse(res.body).dig("result", "addressMatches") || []
    return nil unless matches.size == 1
    m = matches.first
    county = m.dig("geographies", "Counties", 0, "NAME").to_s.sub(/ County\z/, "").presence
    Result.new(lat: m.dig("coordinates", "y"), lon: m.dig("coordinates", "x"), county: county, matched: m["matchedAddress"])
  rescue StandardError => e
    Rails.logger.warn("[census geocoder] #{line}: #{e.class}: #{e.message}")
    nil
  end

  HOME_NAME = /\b(home|house|residence|apt|apartment)\b/i

  # A rider's home saved as a place (named "Home", named only by its street
  # address, or the same street as a rider's home address): left for a person,
  # never sent to the Census.
  def self.looks_like_a_home?(address)
    return true if address.name.to_s =~ HOME_NAME
    street = address.address.to_s.downcase.gsub(/[^a-z0-9 ]/, " ").squish
    return false if street.blank?
    # no place name, only its own street address: as likely someone's house as a business
    name = address.name.to_s.downcase.gsub(/[^a-z0-9 ]/, " ").squish
    return true if name.blank? || name.start_with?(street) || street.start_with?(name)
    Customer.joins(:address).where("lower(regexp_replace(addresses.address, '[^A-Za-z0-9 ]', ' ', 'g')) like ?", "#{street.split.first(2).join(' ')}%")
            .pluck("addresses.address").any? { |s| s.to_s.downcase.gsub(/[^a-z0-9 ]/, " ").squish == street }
  end

  # Pin a saved place that has no pin. -> Result when it was pinned, else nil.
  def self.pin!(address)
    return nil unless address.is_a?(ProviderCommonAddress) && address.the_geom.nil?
    return nil if looks_like_a_home?(address)
    r = lookup(street: address.address, city: address.city, state: address.state, zip: address.zip)
    geom = r && Address.compute_geom(r.lat, r.lon)
    return nil unless geom
    attrs = { the_geom: geom, updated_at: Time.current }
    attrs[:county] = r.county if address.county.blank? && r.county
    address.update_columns(attrs)
    Rails.logger.info("[census geocoder] pinned address #{address.id} #{address.name.inspect} at #{r.lat},#{r.lon} (#{r.matched})")
    r
  end

  # The morning address check (rake addresses:scan): try the active saved places
  # still without a pin. -> [[address, Result], ...] for the email.
  def self.pin_missing!(limit: NIGHTLY_LIMIT)
    ProviderCommonAddress.where(the_geom: nil).where("inactive is null or inactive = ?", false)
      .where.not(address: [nil, ""]).order(updated_at: :desc).limit(limit).filter_map do |a|
      r = pin!(a)
      sleep 0.3
      [a, r] if r
    end
  end
end
