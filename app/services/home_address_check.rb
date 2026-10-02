# Does a saved place look like somebody's home? (Philz 2026-10-02: riders' homes
# kept turning up as shared saved places -- "Home", "Mary Peterson", "86 N Ee
# Hatchett Ave" -- where every CSR sees them in every rider's search.)
# Used by the saved-place dialog (asks "are you sure?") and by CensusGeocoder
# (never sends a home to the Census). -> a short reason, or nil.
class HomeAddressCheck
  HOME_WORDS = /\b(home|house|residence|apt|apartment|mom'?s|dad'?s|grandma'?s)\b/i
  # ...but these are places, not someone's home
  NOT_A_HOME = /\b(nursing|funeral|group|care|boarding|children'?s|senior|ronald mcdonald) home|\bhome (depot|health|care|dialysis|infusion|instead|goods)\b|\b(court ?house|ware ?house|house of)\b/i

  def self.home_name?(name)
    name.to_s =~ HOME_WORDS && name.to_s !~ NOT_A_HOME
  end

  def self.reason(address)
    name = norm(address.name)
    street = norm(address.address)
    return "it's called “#{address.name.strip}”" if home_name?(address.name)
    return "it has no place name, only a street address" if name.blank? || (street.present? && (name.start_with?(street) || street.start_with?(name)))
    return "it's named after a rider" if rider_named?(address.name, address.provider_id)
    return "a rider lives at this address" if rider_lives_at?(street_key(address.address))
    nil
  end

  def self.norm(s)
    s.to_s.downcase.gsub(/[^a-z0-9 ]/, " ").squish
  end

  SUFFIX = { "drive" => "dr", "street" => "st", "avenue" => "ave", "road" => "rd", "boulevard" => "blvd",
             "highway" => "hwy", "lane" => "ln", "court" => "ct", "circle" => "cir", "parkway" => "pkwy",
             "place" => "pl", "east" => "e", "west" => "w", "north" => "n", "south" => "s" }.freeze

  # "2701 Hospital Drive Ste 204" and "2701 Hospital Dr" are the same building.
  def self.street_key(s)
    words = norm(s).sub(/\b(ste|suite|apt|apartment|unit|bldg|building|rm|room|trlr|lot|no)\b.*\z/, "").split
    words.map { |w| SUFFIX[w] || w }.join(" ")
  end

  def self.rider_named?(name, provider_id)
    parts = norm(name).split
    return false unless parts.size.between?(2, 4)
    scope = Customer.where(deleted_at: nil)
    scope = scope.where(provider_id: provider_id) if provider_id
    scope.where("lower(first_name) = ? and lower(last_name) = ?", parts.first, parts.last).exists?
  end

  # A household's home: the riders who live there share a last name (Ludwig and
  # Patricia Uloth). Riders with different last names at one address (a nursing
  # home, an apartment complex, a hospital) make it a facility: a fine saved place.
  def self.rider_lives_at?(street)
    return false if street.blank? || street.split.size < 2
    names = Customer.where(deleted_at: nil).joins(:address)
                    .where("lower(regexp_replace(addresses.address, '[^A-Za-z0-9 ]', ' ', 'g')) like ?", "#{street.split.first(2).join(' ')}%")
                    .pluck("addresses.address", :last_name)
                    .select { |a, _| street_key(a) == street }.map { |_, last| norm(last) }
    names.any? && names.uniq.size == 1
  end
end
