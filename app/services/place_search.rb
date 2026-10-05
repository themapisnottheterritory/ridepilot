require "net/http"

# A place our own map doesn't know by name ("Diane's Hair Salon, Cuero"):
# ask Azure Maps, the way a dispatcher would search the web, and keep the
# answer only if it plainly is the place asked for. Used by Ask RidePilot's
# add/find-a-place card (SavedPlaceProposal) after the saved places and our map
# have had their turn; never per keystroke.
#
#   PlaceSearch.find(name: "Diane's Hair Salon", city: "Cuero", near: { lat: 29.09, lon: -97.29 })
#   # => #<struct lat: 29.090.., lon: -97.324.., name: "Diane's Hair Salon", address: "2010 State Highway 72 West, ...", kind: "business">
#
# Only the place name and town are sent, never a rider. The key comes from
# AZURE_MAPS_KEY (config/application.yml on the server); without it this does
# nothing.
#
# Measured 2026-10-05 against 10 places staff had pinned by hand: Search API
# 2026-01-01 (/geocode) answers a business name with the town centre, so this
# uses Search v1 fuzzy search, which found Diane's Hair Salon 48 m from the
# staff pin and Dollar General in Hallettsville 8 m off. v1 is deprecated
# (no retirement date yet): if it goes, only this file changes.
#
# What is accepted (the same test, with these rules: 4 of 7 business names
# found, the other 3 refused, none wrong):
#   - a business ("POI") whose name matches the one asked for, within
#     NEAR_MILES of the town typed. Unsure, the service returns a confident
#     wrong one (Buc-ee's in Port Lavaca for a Bloomington address,
#     Tru-Skin Dermatology in Bastrop for Hallettsville);
#   - an address ("Point Address") only if its house number is the one typed;
#   - never a town, county or street ("Geography", "Street"): that is the
#     service giving up, not an answer.
class PlaceSearch
  BASE        = ENV.fetch("AZURE_MAPS_URL", "https://us.atlas.microsoft.com")   # US endpoint: processed in the US
  NEAR_MILES  = 12
  STOP_WORDS  = %w[the of and at inc llc co company ctr].freeze
  # address: the whole line; street / city / zip: its parts, to fill the card
  Result = Struct.new(:lat, :lon, :name, :address, :street, :city, :zip, :kind, keyword_init: true)

  def self.key
    ENV["AZURE_MAPS_KEY"].presence
  end

  def self.enabled?
    key.present?
  end

  # A month's calls stop here (well inside Azure's free 5,000). Real use is
  # ~25-50 a month: each place is looked up once, then it is a saved place.
  def self.monthly_cap
    Integer(ENV.fetch("AZURE_MAPS_MONTHLY_CAP", 3000))
  end

  # near: { lat:, lon: } of the town typed. Without it nothing is accepted:
  # an answer can't be checked against a town nobody named.
  def self.find(name:, city:, state: "TX", house_number: nil, near:)
    return nil unless enabled? && near && name.to_s.strip.present?
    return nil unless count_one!
    results = request(query: [name, city, state].compact.join(", "), near: near)
    pick(results, name: name, house_number: house_number, near: near)
  rescue StandardError => e
    report("#{e.class}: #{e.message}")
    nil
  end

  def self.request(query:, near:)
    uri = URI("#{BASE}/search/fuzzy/json")
    uri.query = { "api-version" => "1.0", query: query, countrySet: "US",
                  lat: near[:lat], lon: near[:lon], limit: 5 }.to_query
    req = Net::HTTP::Get.new(uri)
    req["subscription-key"] = key   # a header, so the key is never in a URL or a log
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 3, read_timeout: 5) { |h| h.request(req) }
    raise "Azure Maps answered #{res.code}" unless res.code == "200"
    JSON.parse(res.body)["results"] || []
  end

  def self.pick(results, name:, house_number:, near:)
    Array(results).each do |r|
      pos = r["position"] or next
      at = { lat: pos["lat"].to_f, lon: pos["lon"].to_f }
      next if miles(at, near) > NEAR_MILES
      case r["type"]
      when "POI"
        found = r.dig("poi", "name").to_s
        next unless same_name?(found, name)
        return Result.new(lat: at[:lat].round(6), lon: at[:lon].round(6), name: found, kind: "business", **address_parts(r))
      when "Point Address"
        next unless house_number.present? && r.dig("address", "streetNumber").to_s == house_number.to_s
        return Result.new(lat: at[:lat].round(6), lon: at[:lon].round(6), name: name, kind: "address", **address_parts(r))
      end
    end
    nil
  end

  # "250 Farm-to-Market 766, Cuero, TX 77954" -> street "250 Farm-to-Market 766",
  # city "Cuero", zip "77954"; a business without a house number keeps the part
  # of the line before the first comma as its street.
  def self.address_parts(r)
    a = r["address"] || {}
    street = [a["streetNumber"], a["streetName"]].compact.join(" ").presence ||
             a["freeformAddress"].to_s.split(",").first.to_s.strip.presence
    { address: a["freeformAddress"], street: street, city: a["municipality"].presence, zip: a["postalCode"].to_s[/\d{5}/] }
  end

  # Businesses Azure Maps lists within `metres` of a spot, nearest first, for
  # "Name busy places" (PlaceNamesController#suggest): [{ name:, metres: }].
  # Only offered to a person to choose from; never saved by itself. Each call
  # counts against the monthly cap like a search.
  def self.nearby(lat:, lon:, metres: 60)
    return [] unless enabled? && lat.to_f.nonzero? && lon.to_f.nonzero?
    return [] unless count_one!
    uri = URI("#{BASE}/search/nearby/json")
    uri.query = { "api-version" => "1.0", lat: lat, lon: lon, radius: metres, limit: 6 }.to_query
    req = Net::HTTP::Get.new(uri)
    req["subscription-key"] = key
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 3, read_timeout: 5) { |h| h.request(req) }
    raise "Azure Maps answered #{res.code}" unless res.code == "200"
    (JSON.parse(res.body)["results"] || []).filter_map { |r| r.dig("poi", "name").presence && { name: r.dig("poi", "name"), metres: r["dist"].to_f.round } }
                                          .uniq { |h| h[:name].downcase }.sort_by { |h| h[:metres] }
  rescue StandardError => e
    report("#{e.class}: #{e.message}")
    []
  end

  # Most of the shorter name's words appear in the other; a word may be the
  # start of the other's ("Derm" / "Dermatology", "Supply" / "Supplies").
  def self.same_name?(a, b)
    ta, tb = words(a), words(b)
    return false if ta.empty? || tb.empty?
    short, long = [ta, tb].sort_by(&:size)
    shared = short.count { |w| long.any? { |x| x == w || (w.size >= 4 && x.size >= 4 && (x.start_with?(w[0, 4]) || w.start_with?(x[0, 4]))) } }
    shared.to_f / short.size >= 0.75
  end

  def self.words(text)
    text.to_s.downcase.gsub(/['’]/, "").split(/[^a-z0-9]+/).reject { |w| w.empty? || STOP_WORDS.include?(w) }
  end

  def self.miles(a, b)
    rad = ->(x) { x * Math::PI / 180 }
    h = Math.sin(rad.(b[:lat] - a[:lat]) / 2)**2 + Math.cos(rad.(a[:lat])) * Math.cos(rad.(b[:lat])) * Math.sin(rad.(b[:lon] - a[:lon]) / 2)**2
    2 * 3958.8 * Math.asin(Math.sqrt(h))
  end

  # One file per month in tmp/ (shared by every Puma worker), counted under a
  # lock. false once the month's cap is reached; the trouble board hears once.
  def self.count_one!
    File.open(counter_path, File::RDWR | File::CREAT, 0o644) do |f|
      f.flock(File::LOCK_EX)
      n = f.read.to_i
      if n >= monthly_cap
        if n == monthly_cap   # first refusal of the month: say so once
          report("Azure Maps monthly cap of #{monthly_cap} reached; place lookups fall back to pasting coordinates")
          f.rewind; f.write((n + 1).to_s); f.flush; f.truncate(f.pos)
        end
        return false
      end
      f.rewind; f.write((n + 1).to_s); f.flush; f.truncate(f.pos)
    end
    true
  end

  def self.counter_path
    Rails.root.join("tmp", "azure-maps-#{Time.zone.today.strftime('%Y-%m')}.count")
  end

  def self.report(detail)
    Rails.logger.warn "PlaceSearch: #{detail}"
    TroubleEvent.create(kind: "error", screen: "Ask RidePilot", action: "place_search", detail: TroubleEvent.scrub(detail))
  rescue StandardError
    nil
  end
end
