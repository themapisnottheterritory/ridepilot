# Where the towns our riders use are, from our own addresses: the median pin of
# each town that 3 or more saved addresses carry. No lookups.
#
# The address search keeps every map answer near the town typed (AddressesController
# #geocode_suggest). Replaying every search since Sep 21 (2026-10-06) found map
# answers in the wrong town: "332 Independence Dr, apt 315 Port Lavaca" answered
# Friendswood, "1020 Henry St, Gonzales" Webster, "219 W Seventh St, Apt 35
# Bloomington" downtown Austin. With no town typed, an answer has to be near a
# town we serve.
module TownCentres
  # towns with this many of our addresses make up the area we serve
  SERVED_MIN_ADDRESSES = 30
  SERVED_RADIUS_MILES  = 20
  # a typed town is followed by a street word when it is the street's own name
  # ("4001 Houston Highway", "Goliad St"), not the town
  STREET_WORD = /\A(?:st|street|ave|avenue|rd|road|dr|drive|ln|lane|blvd|boulevard|hwy|highway|ct|court|cir|circle|
                    trl|trail|pkwy|parkway|pl|place|way|loop|station|staion|ter|terrace|bnd|bend|holw|hollow|
                    xing|crossing|cv|cove|run|row|path|walk|plz|plaza|sq|square|pt|point|park|pk)\z/x

  module_function

  # { "port lavaca" => { name: "Port Lavaca", n: 1537, lat: 28.615, lon: -96.628 }, ... }, reloaded daily
  def all
    @all = nil if @loaded_at.nil? || @loaded_at < 1.day.ago
    @all ||= begin
      @loaded_at = Time.current
      ActiveRecord::Base.connection.select_rows(<<~SQL).to_h { |key, name, n, lat, lon| [key, { name: name, n: n.to_i, lat: lat.to_f, lon: lon.to_f }] }
        SELECT lower(trim(city)), initcap(lower(trim(city))), count(*),
               percentile_cont(0.5) WITHIN GROUP (ORDER BY ST_Y(the_geom::geometry)),
               percentile_cont(0.5) WITHIN GROUP (ORDER BY ST_X(the_geom::geometry))
        FROM addresses
        WHERE the_geom IS NOT NULL AND trim(coalesce(city, '')) <> ''
        GROUP BY 1 HAVING count(*) >= 3
      SQL
    end
  end

  # The town typed in an address, or nil: { name:, lat:, lon:, typed: "bloominton" }.
  # The last town in the text wins (the town comes after the street); a town
  # name followed by a street word is the street's name. A word of 6 letters or
  # more one letter off a town ("Bloominton", "Hallettsvile") counts too.
  def find_in(text)
    words = text.to_s.downcase.gsub(/[^a-z0-9 ]/, ' ').split
    towns = all
    (words.size - 1).downto(0) do |i|
      next if words[i + 1] && (words[i + 1] =~ STREET_WORD || words[i + 1] == 'county')   # a street, or the county
      3.downto(1) do |len|
        next if i - len + 1 < 0
        typed = words[(i - len + 1)..i].join(' ')
        town = towns[typed] || near_spelling(typed, towns)
        return town.merge(typed: typed) if town
      end
    end
    nil
  end

  def near_spelling(typed, towns)
    return nil if typed.size < 6 || typed =~ /\d/
    towns.each do |key, town|
      next if (key.size - typed.size).abs > 2
      allowed = key.size >= 9 ? 2 : 1
      return town if DidYouMean::Levenshtein.distance(typed, key) <= allowed
    end
    nil
  end

  def miles(town, lat, lon)
    rad = ->(x) { x * Math::PI / 180 }
    a = Math.sin(rad.(lat - town[:lat]) / 2)**2 +
        Math.cos(rad.(town[:lat])) * Math.cos(rad.(lat)) * Math.sin(rad.(lon - town[:lon]) / 2)**2
    2 * 3958.8 * Math.asin(Math.sqrt(a))
  end

  # The box around the towns we serve, a few miles wide of the outermost:
  # { min_lat:, max_lat:, min_lon:, max_lon: }. The provider's own box runs
  # from San Antonio to Houston, so a search by name alone ("walmart",
  # "dialysis") got Nominatim's five best in Houston and Conroe, and none of
  # ours. Name searches ask inside this box first (AddressesController
  # #nominatim_fetch).
  SERVED_BOX_PAD = 0.15   # degrees, about 10 miles

  def served_box
    towns = all.values.select { |t| t[:n] >= SERVED_MIN_ADDRESSES }
    return nil if towns.empty?
    lats = towns.map { |t| t[:lat] }
    lons = towns.map { |t| t[:lon] }
    { min_lat: lats.min - SERVED_BOX_PAD, max_lat: lats.max + SERVED_BOX_PAD,
      min_lon: lons.min - SERVED_BOX_PAD, max_lon: lons.max + SERVED_BOX_PAD }
  end

  # Near one of the towns we serve
  def served?(lat, lon)
    all.values.any? { |t| t[:n] >= SERVED_MIN_ADDRESSES && miles(t, lat, lon) <= SERVED_RADIUS_MILES }
  end
end
