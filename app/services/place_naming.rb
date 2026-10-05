# Busy trip destinations that have no name ("2401 Patterson Drive" instead of
# the clinic riders call about), and giving them one.
#
# Call-takers answer "can you confirm my trip to Victoria Heart and Vascular?"
# all day (three people, ~325 calls on 2026-10-05), and a trip booked to a typed
# address shows only the street. In October 2026, 133 places used by Victoria
# Transit's trips (794 pickups and drop-offs in 60 days) had no name anywhere.
#
#   PlaceNaming.unnamed_destinations(provider)   # busiest first
#   PlaceNaming.name_place!(provider:, user:, address_ids:, name:, address_group_id:)
#     # -> a saved place with that name, and every unnamed address record at the
#     #    same street address renamed, so trips already booked show it too
#   PlaceNaming.saved_name_for(address)          # a new typed address takes a
#                                                # saved place's name (Address callback)
#
# The page is PlaceNamesController (Saved places -> "Name busy places").
module PlaceNaming
  module_function

  WINDOW_BACK  = 30.days
  WINDOW_AHEAD = 30.days
  NEAR_METRES  = 25    # a typed address this close to a saved place, same house number, is that place

  SUFFIXES = { "drive" => "dr", "street" => "st", "avenue" => "ave", "road" => "rd", "boulevard" => "blvd",
               "lane" => "ln", "highway" => "hwy", "parkway" => "pkwy", "court" => "ct", "circle" => "cir",
               "place" => "pl", "north" => "n", "south" => "s", "east" => "e", "west" => "w" }.freeze

  # "2401 Patterson Drive" and "2401 PATTERSON DR." -> "2401 patterson dr"
  def key(address_line)
    address_line.to_s.downcase.tr(".,#", "   ").split.map { |w| SUFFIXES[w] || w }.join(" ")
  end

  def place_key(address)
    [key(address.address), address.city.to_s.downcase.strip].join("|")
  end

  # An apartment, unit, lot or trailer number: somebody's home, not a facility
  # (a clinic's "Suite 100" stays in).
  RESIDENCE = /\b(?:apt|apartment|unit|lot|trlr|trailer|space|spc)\b\.?\s*\S|#\s*\w/i

  # Unnamed places this provider's trips go to or from in the window, busiest
  # first: { key:, address:, city:, state:, zip:, lat:, lon:, trips:, address_ids: }.
  # Riders' homes are not destinations to name: an address with an apartment
  # or unit number, or one that is any rider's saved "Home", is left out (busy
  # riders made their homes the top of the list on the first try, 2026-10-05).
  def unnamed_destinations(provider, now: Time.zone.now, limit: 100)
    homes = home_keys
    places = {}
    Trip.where(deleted_at: nil, provider_id: provider.id)
        .where(pickup_time: (now.beginning_of_day - WINDOW_BACK)..(now + WINDOW_AHEAD))
        .includes(:pickup_address, :dropoff_address).find_each do |t|
      [t.pickup_address, t.dropoff_address].each do |a|
        next if a.nil? || a.name.present? || a.address.blank? || a.address.match?(RESIDENCE)
        k = place_key(a)
        next if homes.include?(k)
        p = places[k] ||= { key: k, address: a.address, city: a.city, state: a.state, zip: a.zip,
                            lat: a.latitude&.to_f, lon: a.longitude&.to_f, trips: 0, address_ids: [] }
        p[:trips] += 1
        p[:address_ids] |= [a.id]
        p[:lat] ||= a.latitude&.to_f
        p[:lon] ||= a.longitude&.to_f
      end
    end
    # already a saved place at that address (booked as a typed copy): offer its name
    places.each_value do |p|
      s = saved_place_at(provider, p[:key])
      p[:saved_name] = s&.name
    end
    skipped = skipped_keys(provider)
    places.values.reject { |p| skipped.include?(p[:key]) }.sort_by { |p| -p[:trips] }.first(limit)
  end

  # Every rider's saved home, as place keys ("Home", "Home Rural", "Home-DeWitt"...)
  def home_keys
    CustomerCommonAddress.where("name ILIKE ?", "home%").pluck(:address, :city)
                         .map { |addr, city| [key(addr), city.to_s.downcase.strip].join("|") }.to_set
  end

  # Give a place a name: a saved place for the provider, and the name on every
  # unnamed address record at that street address (the ones listed, and any
  # other unnamed copy of the same address), so the trips already booked to it
  # show the name in Dispatch, on manifests and on the rider's page.
  def name_place!(provider:, user:, address_ids:, name:, address_group_id:)
    name = name.to_s.squish
    raise ArgumentError, "a name is needed" if name.blank?
    base = Address.where(id: address_ids).where.not(address: [nil, ""]).first or raise ArgumentError, "no such address"
    k = place_key(base)
    renamed = 0
    saved = nil
    PaperTrail.request(whodunnit: user&.id&.to_s) do
      Address.transaction do
        # a saved place already at this address is used, not duplicated
        saved = saved_place_at(provider, k) || ProviderCommonAddress.create!(
          provider: provider, name: name, address_group_id: address_group_id,
          address: base.address, city: base.city, state: base.state, zip: base.zip, county: base.try(:county),
          the_geom: base.the_geom, in_district: base.in_district
        )
        number = base.address.to_s[/\A\s*(\d+)/, 1]
        candidates = Address.where(name: [nil, ""]).where.not(id: saved.id)
        candidates = candidates.where("address ILIKE ?", "#{number}%") if number
        candidates.find_each do |a|
          next unless place_key(a) == k || (address_ids.map(&:to_i).include?(a.id))
          a.update_columns(name: name, updated_at: Time.current)   # a label only; no geocoding, no lock bump
          renamed += 1
        end
      end
    end
    { saved_place: saved, renamed: renamed }
  end

  def saved_place_at(provider, place_key_value)
    number = place_key_value[/\A(\d+)/, 1] or return nil
    ProviderCommonAddress.where(provider_id: provider.id).where("inactive IS NULL OR inactive = false")
                         .where("address ILIKE ?", "#{number}%").find { |s| place_key(s) == place_key_value && real_name?(s) }
  end

  # Once, at deploy and whenever saved places were added in bulk: unnamed trip
  # addresses that ARE a saved place take its name (same rule as a new typed
  # address). Only blank names are filled. Returns how many.
  def backfill!(provider, now: Time.zone.now)
    count = 0
    ids = Trip.where(deleted_at: nil, provider_id: provider.id).where("pickup_time >= ?", now.beginning_of_day - WINDOW_BACK)
              .pluck(:pickup_address_id, :dropoff_address_id).flatten.compact.uniq
    PaperTrail.request(whodunnit: "place-naming-backfill") do
      Address.where(id: ids, name: [nil, ""]).find_each do |a|
        next unless (n = saved_name_for(a))
        a.update_columns(name: n, updated_at: Time.current)
        count += 1
      end
    end
    count
  end

  # The saved place a new address is: same street address and town, or within
  # NEAR_METRES with the same house number. Its name, or nil.
  def saved_name_for(address)
    return nil if address.address.blank?
    number = address.address.to_s[/\A\s*(\d+)/, 1] or return nil
    k = place_key(address)
    scope = ProviderCommonAddress.where("inactive IS NULL OR inactive = false").where("address ILIKE ?", "#{number}%")
    scope = scope.where(provider_id: address.provider_id) if address.provider_id
    match = scope.find { |s| place_key(s) == k && real_name?(s) }
    if !match && address.the_geom.present?
      match = scope.where.not(the_geom: nil).find do |s|
        next false unless real_name?(s)
        metres(address.latitude.to_f, address.longitude.to_f, s.latitude.to_f, s.longitude.to_f) <= NEAR_METRES
      end
    end
    match && real_name?(match) ? match.name : nil
  end

  # A saved place's name worth copying onto trips: not a street address saved
  # as a name ("332 Independence Drive Apt 315", "103 N Star": riders' homes
  # saved as places by mistake, found in the first backfill preview, 2026-10-05).
  def real_name?(saved)
    n = saved.name.to_s.strip
    n.present? && n !~ /\A\d/ && key(n) != key(saved.address) && n !~ RESIDENCE && saved.address.to_s !~ RESIDENCE   # not an apartment
  end

  def metres(lat1, lon1, lat2, lon2)
    rad = ->(x) { x * Math::PI / 180 }
    h = Math.sin(rad.(lat2 - lat1) / 2)**2 + Math.cos(rad.(lat1)) * Math.cos(rad.(lat2)) * Math.sin(rad.(lon2 - lon1) / 2)**2
    2 * 6_371_000 * Math.asin(Math.sqrt(h))
  end

  # "Not a facility" (an apartment, a rider's second address): hidden from the
  # list for good. One small file per provider in tmp/, shared by every worker.
  def skip!(provider, key)
    path = skip_path(provider)
    File.open(path, File::RDWR | File::CREAT, 0o644) do |f|
      f.flock(File::LOCK_EX)
      keys = (JSON.parse(f.read) rescue [])
      keys |= [key]
      f.rewind; f.write(JSON.generate(keys)); f.flush; f.truncate(f.pos)
    end
  end

  def skipped_keys(provider)
    JSON.parse(File.read(skip_path(provider))) rescue []
  end

  def skip_path(provider)
    Rails.root.join("tmp", "place-naming-skipped-#{provider.id}.json")
  end
end
