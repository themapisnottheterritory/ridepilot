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
class SavedPlaceProposal
  NOMINATIM = ENV["NOMINATIM_URL"] || "http://10.0.0.18:8088"
  STATE     = ENV["NOMINATIM_FALLBACK_STATE"] || "TX"
  FAR_MILES = 12    # a pin this far from the typed town gets a warning (verify_address_pins.py uses the same)

  attr_reader :name, :address, :city, :state, :zip, :category, :pin, :existing, :warnings

  def initialize(provider:, user:, name:, address:, city: nil, state: nil, zip: nil, category: nil)
    @provider, @user = provider, user
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

  def check
    @existing = find_existing
    @pin      = locate
    @town     = town_centre
    if @pin.nil?
      @warnings << "The map doesn't know this address yet. Drag the pin onto the building, then add it."
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
      kind: "add_saved_place", name: @name, address: @address, city: @city, state: @state, zip: @zip,
      address_group_id: @category&.id,
      groups: AddressGroup.order(:id).pluck(:id, :name).reject { |_, n| n == AddressGroup::UNKNOWN_TYPE },
      pin: @pin, map_center: @pin || @town || default_center, on_map: @pin.present?,
      existing: @existing.map { |a| { id: a.id, name: a.name, address: a.address, city: a.city, on_map: a.the_geom.present? } },
      warnings: @warnings, can_add: can_add?
    }
  end

  # One line for the chat, above the card.
  def summary
    place = @name == @address ? @address : "**#{@name}**, #{@address}"
    town  = [@city, @zip].compact.join(" ")
    lines = ["I can add #{place}#{", #{town}" if town.present?} as a saved place#{" under #{@category.name}" if @category}."]
    if @existing.any?
      names = @existing.first(3).map { |a| "#{a.name} (#{a.address}#{', not on the map' unless a.the_geom})" }
      lines << "Already saved and close to this: #{names.join('; ')}. Add it only if it is really a different place."
    end
    lines << "Check the details below and click **Add it**." if can_add?
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

  # Structured then free-text, accepting only a hit carrying the typed house
  # number (a street-level hit would pin the whole road's midpoint).
  def locate
    return nil unless house_number
    queries = [{ street: @address, city: @city, state: @state }.compact, { q: [@address, @city, @state].compact.join(", ") }]
    queries.each do |q|
      nominatim("/search", q.merge(limit: 5)).each do |hit|
        number = hit.dig("address", "house_number").to_s.split("-").first
        return { lat: hit["lat"].to_f.round(6), lon: hit["lon"].to_f.round(6) } if number == house_number
      end
    end
    nil
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
