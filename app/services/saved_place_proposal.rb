require "open-uri"

# Ask RidePilot, step two of "it fills, they save": turn an "add a saved place"
# request (HelpIntent) into a card the person can check and click. Ruby does
# the checking, the model only read the message:
#
#   - is it already in this agency's address book (same number and street, or
#     the same name)?
#   - can the map place it? If so, where; if not, where should the map open so
#     the pin can be dragged onto the building?
#   - is the pin a long way from the town typed?
#   - may this person add saved places at all?
#
# Nothing is saved here; HelpController#act does that when the button is
# clicked, under the person's own permissions.
#
# mode: :find is "can you find 311 Spring Green Blvd?": the same card, worded
# as a lookup; the place can still be added from it.
class SavedPlaceProposal
  NOMINATIM = ENV["NOMINATIM_URL"] || "http://10.0.0.18:8088"
  STATE     = ENV["NOMINATIM_FALLBACK_STATE"] || "TX"
  FAR_MILES = 12    # a pin this far from the typed town gets a warning (verify_address_pins.py uses the same)

  attr_reader :name, :address, :city, :state, :zip, :category, :pin, :pin_kind, :existing, :warnings, :mode

  def initialize(provider:, user:, name:, address:, city: nil, state: nil, zip: nil, category: nil, mode: :add)
    @provider, @user, @mode = provider, user, mode.to_sym
    @name     = name.presence || address.to_s
    @address  = address.to_s.squish
    @city     = city.to_s.squish.titleize.presence
    @state    = (state.presence || STATE).to_s.upcase.first(2)
    @zip      = zip.to_s[/\d{5}/]
    @category = AddressGroup.find_by(name: category) if category.present?
    @warnings = []
  end

  def house_number
    @address[/\A\d+/]
  end

  def can_add?
    Ability.new(@user).can?(:new, ProviderCommonAddress)
  end

  def street
    @address.sub(/\A\d+\s*/, "")
  end

  # pin_kind: "exact" (the map has that building), "estimate" (it places the
  # number along the street's address range), "street" (it knows the
  # street, not the number: the pin is somewhere on it), "landmark" (a find by
  # name), "business" (our map didn't have it; Azure Maps found the place by
  # its name, see PlaceSearch), or nil (not on our map: the map opens on the town).
  def check
    @existing = find_existing
    @pin, @pin_kind = locate
    @town     = town_centre
    ask_azure_for_business
    paste = "find the building in Google Maps, right-click it, click the numbers at the top of the menu to copy them, and paste them in the box above the map"
    if @pin.nil?
      @warnings << "#{street.presence || @address} isn't on our map yet (it may be a new street). To place the pin, #{paste}. Or search for something nearby."
    elsif @pin_kind == "estimate"
      @warnings << "The map estimates where number #{house_number} falls on #{street}; it can be off by a block or more. Check the pin is on the building, or #{paste}."
    elsif @pin_kind == "street"
      @warnings << "The map knows #{street} but not number #{house_number}, so the pin is somewhere on the street. Slide it to the building, or #{paste}."
    elsif @pin_kind == "business"
      @warnings << "Our map didn't have this; Azure Maps lists #{@found.name} at #{@found.address}. Check the pin is on the right building before adding it."
    elsif @town && (d = miles(@pin, @town)) >= FAR_MILES
      @warnings << "The map puts this #{d.round} miles from #{@city}. Check the pin before adding it."
    end
    @warnings << "Only admins and editors can add saved places; ask Kristie or GCRPC I.T. to add it." unless can_add?
    self
  end

  # What the panel draws: the fields to confirm, the pin (or where to open the
  # map), near matches already saved, warnings, and whether the button shows.
  def to_h
    {
      kind: "add_saved_place", mode: @mode.to_s, pin_kind: @pin_kind,
      name: @name, address: @address, city: @city, state: @state, zip: @zip,
      address_group_id: @category&.id,
      groups: AddressGroup.order(:id).pluck(:id, :name).reject { |_, n| n == AddressGroup::UNKNOWN_TYPE },
      pin: @pin, map_center: @pin || @town || default_center, on_map: %w[exact estimate landmark business].include?(@pin_kind),
      existing: @existing.map { |a| { id: a.id, name: a.name, address: a.address, city: a.city, on_map: a.the_geom.present? } },
      warnings: @warnings, can_add: can_add?
    }
  end

  # One line for the chat, above the card.
  def summary
    place = @name == @address ? @address : "**#{@name}**, #{@address}"
    town  = [@city, @zip].compact.join(" ")
    where = "#{place}#{", #{town}" if town.present?}"
    lines = if @mode == :find
      [case @pin_kind
       when "exact", "landmark" then "Here's #{where} on the map."
       when "business" then "Here's #{where} on the map (found on Azure Maps)."
       when "estimate" then "Here's about where #{where} is on the map."
       when "street" then "I found #{street} on the map, but not number #{house_number}."
       else "I couldn't find #{where} on our map."
       end]
    else
      ["I can add #{where} as a saved place#{" under #{@category.name}" if @category}."]
    end
    if @existing.any?
      names = @existing.first(3).map { |a| "#{a.name} (#{a.address}#{', not on the map' unless a.the_geom})" }
      lines << "Already saved and close to this: #{names.join('; ')}. Add it only if it is really a different place."
    end
    if can_add?
      lines << (@mode == :find ? "To keep it as a saved place, give it a name below and click **Add it**." : "Check the details below and click **Add it**.")
    end
    lines.join("\n\n")
  end

  private

  def find_existing
    scope = ProviderCommonAddress.where(provider_id: @provider.id).where("inactive IS NULL OR inactive = false")
    street_word = @address.sub(/\A\d+\s*/, "")[/[A-Za-z]+/]
    matches = house_number && street_word ? scope.where("address ILIKE ?", "#{house_number} #{street_word}%").to_a : []
    if @name != @address && @name.length >= 4
      matches += scope.where("name ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(@name)}%").to_a
    end
    matches.uniq.first(5)
  end

  # [pin, kind]. With a house number: structured then free text, taking only a
  # hit that carries that number; failing that, the street itself (a pin
  # somewhere on the right road beats the middle of town). Without one (a find
  # by name, "the Walmart on Navarro"): the first hit for the words typed.
  def locate
    at = ->(hit) { { lat: hit["lat"].to_f.round(6), lon: hit["lon"].to_f.round(6) } }
    unless house_number
      return [nil, nil] unless @mode == :find
      words = [(@name unless @name == @address), @address, @city, @state].compact.join(", ")
      hit = nominatim("/search", { q: words, limit: 1 }).first
      return hit ? [at.(hit), "landmark"] : [nil, nil]
    end
    queries = [{ street: @address, city: @city, state: @state }.compact, { q: [@address, @city, @state].compact.join(", ") }]
    queries.each do |q|
      nominatim("/search", q.merge(limit: 5)).each do |hit|
        next unless number_of(hit) == house_number
        return [at.(hit), estimated?(hit) ? "estimate" : "exact"]
      end
    end
    # A numbered road (TX 72, FM 953, CR 105): the map spells it by route number
    # and gives an address just outside the town limit no town at all, so
    # "2010 State Highway 72 W, Cuero" found nothing in Cuero (Michelle,
    # 2026-10-05). Ask again in the map's spelling without the town, keep only
    # that house number, and take the one with the ZIP typed, else the one
    # nearest the town.
    if AddressSpelling.numbered_road?(@address)
      spelled = AddressSpelling.route(@address)
      hits = [{ street: spelled, state: @state }.compact, { q: [spelled, @state].compact.join(", ") }]
               .flat_map { |q| nominatim("/search", q.merge(limit: 10)) }
               .select { |hit| number_of(hit) == house_number }
               .uniq { |hit| [hit["lat"], hit["lon"]] }
      if (best = nearest_to_town(hits))
        return [at.(best), estimated?(best) ? "estimate" : "exact"]
      end
    end
    road_name = AddressSpelling.numbered_road?(street) ? AddressSpelling.route(street) : street
    road = nominatim("/search", { street: road_name, city: @city, state: @state, limit: 1 }.compact).first
    road && road["class"] == "highway" ? [at.(road), "street"] : [nil, nil]
  end

  def number_of(hit)
    hit.dig("address", "house_number").to_s.split("-").first
  end

  # a real address point is a node or a building; a place/house *way* is
  # Nominatim estimating along an address range, and a number past the end of
  # the range lands on the end of the road ("9999 N Navarro St")
  def estimated?(hit)
    hit["class"] == "place" && hit["type"] == "house" && hit["osm_type"] == "way"
  end

  # Of several places with the right number on a numbered road (TX 72 runs
  # through Yorktown, Cuero and Kenedy): the one in the ZIP typed, else the one
  # nearest the town typed, if it is within FAR_MILES; with no town, only an
  # unambiguous single answer.
  def nearest_to_town(hits)
    return nil if hits.empty?
    if @zip.present? && (z = hits.find { |h| h.dig("address", "postcode").to_s.start_with?(@zip.to_s[0, 5]) })
      return z
    end
    centre = town_centre
    return (hits.one? ? hits.first : nil) unless centre
    pt = ->(h) { { lat: h["lat"].to_f, lon: h["lon"].to_f } }
    best = hits.min_by { |h| miles(centre, pt.(h)) }
    miles(centre, pt.(best)) <= FAR_MILES ? best : nil
  end

  # Our map has no exact pin for a place given by name (or a name search landed
  # far from the town): look the business up by its name on Azure Maps, which
  # knows the small local places our map doesn't (Diane's Hair Salon, Cuero,
  # 2026-10-05). An exact pin from our map is never second-guessed.
  def ask_azure_for_business
    return unless @town && business_name?
    weak = @pin.nil? || %w[estimate street].include?(@pin_kind) ||
           (@pin_kind == "landmark" && miles(@pin, @town) >= FAR_MILES)
    return unless weak
    hit = PlaceSearch.find(name: @name, city: @city, state: @state || STATE, house_number: house_number, near: @town)
    return unless hit
    @pin, @pin_kind, @found = { lat: hit.lat, lon: hit.lon }, "business", hit
  end

  # a real name, not the address repeated or a bare number
  def business_name?
    @name.present? && @name != @address && @name !~ /\A\s*\d/
  end

  def town_centre
    return nil unless @city
    hit = nominatim("/search", { city: @city, state: @state, limit: 1 }).first
    hit && { lat: hit["lat"].to_f.round(5), lon: hit["lon"].to_f.round(5) }
  end

  def default_center
    b = Utility.new.get_provider_bounds(@provider)
    b ? { lat: (b[:min_lat] + b[:max_lat]) / 2.0, lon: (b[:min_lon] + b[:max_lon]) / 2.0 } : { lat: 28.8053, lon: -97.0036 }
  end

  def nominatim(path, params)
    query = { format: "json", addressdetails: 1, countrycodes: "us" }.merge(params)
    ActiveSupport::JSON.decode(OpenURI.open_uri("#{NOMINATIM}#{path}?#{query.to_query}", open_timeout: 3, read_timeout: 5).read)
  rescue StandardError => e
    Rails.logger.warn "SavedPlaceProposal #{path} failed: #{e.class}: #{e.message}"
    []
  end

  def miles(a, b)
    rad = ->(x) { x * Math::PI / 180 }
    h = Math.sin(rad.(b[:lat] - a[:lat]) / 2)**2 + Math.cos(rad.(a[:lat])) * Math.cos(rad.(b[:lat])) * Math.sin(rad.(b[:lon] - a[:lon]) / 2)**2
    2 * 3958.8 * Math.asin(Math.sqrt(h))
  end
end
