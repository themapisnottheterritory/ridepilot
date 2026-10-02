# Turn a typed address into a map point even when our map (self-hosted Nominatim,
# Texas OSM) doesn't know the house number: try it as typed, then without the
# house number, then without the ZIP, then without the state (then the same
# without a leading N/S/E/W), and put the
# typed house number back on the street that matched. The pin lands on the
# right street, close enough to book and route.
#
# Used by the trip form (TypedAddressResolution#geocode_relaxed) and, from
# 2026-10-02, by the rider's address dialog: "Place it on the street" (Michelle
# hit house numbers the suggestions didn't know). -> stringified attrs hash
# (address/city/state/zip/lat/lon, and 'exact' when the map knew the house
# itself rather than just the street) or nil.
class RelaxedGeocoder
  def self.call(text, provider)
    house_number = text[/\A\s*(\d+)\s+/, 1]
    no_house     = text.sub(/\A\s*\d+\s+/, '')
    drop_zip     = ->(s) { s.sub(/,?\s*\d{5}(?:-\d{4})?\s*\z/, '').strip.sub(/,\s*\z/, '') }
    drop_st_zip  = ->(s) { s.sub(/,?\s*(?:tx|texas)\b.*\z/i, '').strip.sub(/,\s*\z/, '') }

    # "2207 E Walnut Ave": the map knows only "Walnut Avenue" (2026-10-02), so the
    # leading direction goes too, after the forms that keep it have been tried.
    no_dir       = ->(s) { s.sub(/\A(\s*\d+\s+)?(?:n|s|e|w|north|south|east|west)\.?\s+/i, '\\1') }

    # The house number is kept for the first tries: the map often knows the house
    # under a plainer spelling ("2207 Walnut Ave" found it, 8 m from the Census point).
    variants = [text, no_dir.call(text), drop_zip.call(no_dir.call(text)), no_house, drop_zip.call(no_house), drop_st_zip.call(no_house),
                no_dir.call(no_house), drop_zip.call(no_dir.call(no_house)), drop_st_zip.call(no_dir.call(no_house))]
                 .map { |s| s.to_s.strip }.reject(&:blank?).uniq

    # Every spelling is tried for the house itself before settling for the street.
    street_hit = nil
    variants.each do |q|
      results = GeocodingService.new(q, provider).execute
      next if results.blank?
      r = results.first.stringify_keys
      r['exact'] = house_number.present? && r['address'].to_s =~ /\A#{Regexp.escape(house_number)}\b/ ? true : false
      return r if r['exact']
      street_hit ||= r
    end
    if street_hit
      # Re-attach the dispatcher's house number to the street that matched.
      if house_number.present? && street_hit['address'].present?
        street_hit['address'] = "#{house_number} #{street_hit['address']}"
      end
      return street_hit
    end
    nil
  end
end
