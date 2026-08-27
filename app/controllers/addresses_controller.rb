require 'open-uri'

class AddressesController < ApplicationController
  # No load_resource: this controller has no edit/update/destroy actions (and no
  # routes to them), so the old `load_resource only: [...]` referenced callbacks
  # that could never fire -- which Rails 7.1 raises on, breaking every spec in
  # this file. authorize_resource still guards the collection actions.
  authorize_resource

  # Nominatim matches whole tokens only -- it has no prefix search -- so there
  # is no point querying it before the user has typed a word.
  MIN_SUGGEST_LENGTH = 3
  # Structured search returns nothing at all without an explicit state.
  NOMINATIM_FALLBACK_STATE = ENV['NOMINATIM_FALLBACK_STATE'] || 'TX'

  # A saved address reaches the picker as Address#one_line_text -- a label of
  # the form "Home (2501 E Mockingbird Ln APT 3502 Victoria, TX 77904)". Editing
  # that text in place is the obvious way to retarget a leg, and it used to find
  # nothing at all: the name and bracket travel to Nominatim with the address,
  # and a half-deleted label arrives with the bracket unclosed, which is why the
  # closer is optional here.
  #
  # The inside must start with a house number before we unwrap it. Without that
  # a genuine "1404 E Virginia (rear entrance)" would be searched as "rear
  # entrance" -- the note instead of the address.
  LABELLED_ADDRESS = /\A[^()]+\(\s*(?<addr>\d[^()]*?)\s*\)?\z/
  SUGGEST_LIMIT = 5

  # provider & customer common addresses
  def trippable_autocomplete
    term = parse_search_term

    #three ways to match:
    #- name
    #- building name
    #- substring of textified address (split at comma into address,
    #  city/state/zip)

    address, city_state_zip = term.split(",")
    address.strip!
    if city_state_zip
      city_state_zip.strip!
    else
      city_state_zip = ''
    end

    arel_table = Address.arel_table

    if params[:customer_id].present? 
      customer = Customer.find_by_id(params[:customer_id])
      base_arel = (arel_table[:customer_id].in(customer.id).and(arel_table[:type].eq('CustomerCommonAddress')))
      if customer
        base_arel = base_arel.or(arel_table[:provider_id].in(customer.authorized_provider_ids).and(arel_table[:type].eq('ProviderCommonAddress')))
      end
    else
      base_arel = arel_table[:provider_id].eq(current_provider_id).and(arel_table[:type].eq('ProviderCommonAddress'))
    end

    addresses = Address.where(base_arel.to_sql)
      .where('inactive is NULL or inactive != ?', true)
      .where.not(the_geom: nil)
      .where(["((LOWER(address) like '%' || ? || '%' ) and  (city || ', ' || state || ' ' || zip like ? || '%')) or LOWER(building_name) like '%' || ? || '%' or LOWER(name) like '%' || ? || '%' ", address, city_state_zip, term, term])

    if params[:exclude].present?
      addresses = addresses.where.not(id: params[:exclude].split(','))
    end

    if addresses.size > 0
      #there are some existing addresses
      address_json = addresses.map { |address| address.json }
    end

    respond_to do |format|
      format.json { render json: address_json || [] }
    end
  end

  def autocomplete_public
    term = parse_search_term

    address_json = GeocodingService.new(term, current_provider).execute

    render :json => address_json
  end


  def validate_customer_specific
    the_geom       = process_geom
    prefix         = params['prefix'] || ""
    address_params = {}

    # Some kind of faux strong parameters...
    for param in ['name', 'building_name', 'address', 'city', 'state', 'zip', 'phone_number', 'in_district', 'trip_purpose_id', 'notes']
      address_params[param] = params[prefix][param]
    end
    
    address_params[:the_geom]    = the_geom if the_geom

    if params[:address_id].present?
      address = CustomerCommonAddress.find_by_id(params[:address_id])
      address.attributes = address_params
    else
      address_params[:provider_id] = current_provider_id
      address = CustomerCommonAddress.new(address_params)
    end

    if address.valid?
      render :json => {
        success: true,
        prefix: prefix,
        address_text: address.address_text,
        attributes: address.as_json
      }
    else
      # errors.messages is frozen on Rails 7.1; mutating it raised FrozenError
      # and returned a 500, which the address dialog swallowed silently.
      errors = address.errors.messages.deep_dup
      errors[:prefix] = prefix
      render :json => errors
    end
  end

  # Suggestion source for the browser-side address pickers.
  #
  # Two passes on purpose. Nominatim's free-text search cannot resolve a house
  # number against a street whose name collides with a place name -- "1404 E
  # Virginia" returns nothing, because "Virginia" reads as the state -- unless
  # the street type is spelled out ("1404 E Virginia Ave"). Its structured
  # search resolves the same string without the street type, but only when
  # given an explicit state. So: free text first, structured as a fallback.
  # The fallback runs only when free text found nothing, so it can add matches
  # but never change ones that already worked.
  def geocode_suggest
    term = params[:q].to_s.strip
    term = Regexp.last_match[:addr] if term.match(LABELLED_ADDRESS)
    return render(json: []) if term.length < MIN_SUGGEST_LENGTH

    # Free text and structured search answer differently, and neither is reliably
    # the better one. "2001 Palm Village" free-text returns a Palm Court in
    # Bridgeland; structured returns 2001 Palm Village Boulevard in Bay City,
    # which is the address being typed. Running them as a chain -- structured
    # only when free text came back empty -- meant a poor first answer hid the
    # right second one, and the dispatcher saw only the poor one.
    typed_number = term[/\A\s*(\d+)/, 1]
    results = nominatim_suggest(q: term)

    # The second pass costs another round trip, so it is only spent when the
    # first looks unconvincing: nothing at all, or nothing carrying the house
    # number that was typed. A free-text hit on the right number needs no help.
    unless convincing_suggestions?(results, typed_number)
      results += nominatim_suggest(street: term, state: NOMINATIM_FALLBACK_STATE)
    end

    # Dispatchers type the apartment, because the apartment is where the rider
    # lives: "1801 Palm Village Blvd #143", "2300 Hamman Rd APT D1", "1408
    # Whitson 6a". Nominatim matches none of those and the unit is not something
    # it holds anyway. Drop it and ask again -- of eight real examples from Bay
    # City, all eight found nothing as typed and six resolved exactly this way.
    if results.empty? && (without_unit = strip_unit(term)) != term
      results = nominatim_suggest(q: without_unit)
      results += nominatim_suggest(street: without_unit, state: NOMINATIM_FALLBACK_STATE) unless
        convincing_suggestions?(results, typed_number)
    end

    results = rank_suggestions(results, typed_number)
    results = carry_typed_house_number(results, typed_number)

    # Last resort: a partial street ("1404 E Vir") that Nominatim cannot match
    # in any form, completed from the local dictionary.
    results = street_dictionary_suggest(term) if results.empty?

    render json: results.first(SUGGEST_LIMIT)
  end

  private

  # Returns raw Nominatim JSON; the pickers already know how to parse that shape.
  # Everything from an apartment or unit marker onward, and a trailing scrap like
  # "6a" or "R170". A trailing token has to contain a digit to be dropped, which
  # is what keeps "1105 E Broadway ST" and "374 5th St South" intact -- a street
  # type and a directional are not units.
  UNIT_MARKER = /\s*(?:#|\b(?:apt|apartment|ste|suite|unit|rm|room|trlr|trailer|lot|bldg|building|no)\b\.?).*\z/i
  TRAILING_SCRAP = /\s+(?=\S*\d)\S{1,5}\z/

  # On a rural route the trailing number IS the road -- "265 CR 181", "2620 FM
  # 1760", "8 Pvt RD 1192" -- so the scrap rule has to stand down for those or it
  # amputates the address it was meant to repair.
  ROUTE_TAIL = /\b(?:fm|cr|rr|rd|hwy|highway|us|sh|tx|loop|spur|route|farm)\s+\S*\d\S*\z/i

  def strip_unit(term)
    base = term.sub(UNIT_MARKER, '').strip
    base = base.sub(TRAILING_SCRAP, '').strip unless base =~ ROUTE_TAIL
    base.length >= MIN_SUGGEST_LENGTH ? base : term
  end

  # When the geocoder can only place the street -- OSM has 1st Street in Bay City
  # but not number 2212 on it -- keep the number that was typed. Dropping it
  # silently saved "1st Street" with the centreline coordinates, which looks
  # right on the form and sends the bus to the middle of the road. The street is
  # confirmed; the number is the dispatcher's, and it belongs in the address.
  def carry_typed_house_number(results, typed_number)
    return results if typed_number.blank?

    results.map do |r|
      next r if r.dig('address', 'house_number').present?
      next r if r.dig('address', 'road').blank?

      r = r.deep_dup
      r['address']['house_number'] = typed_number
      r['display_name'] = "#{typed_number} #{r['display_name']}"
      r
    end
  end

  # Whether the geocoder's first answer is good enough to stop at. With a house
  # number typed, only a result carrying that number counts -- otherwise every
  # vaguely street-shaped match would end the search.
  def convincing_suggestions?(results, typed_number)
    return false if results.empty?
    return true  if typed_number.nil?

    results.any? { |r| r.dig('address', 'house_number') == typed_number }
  end

  # Lift the results that carry the number that was typed, then those that carry
  # any number, above the rest. Nominatim's own ordering is preserved inside each
  # band, so this promotes better answers rather than reshuffling the list.
  def rank_suggestions(results, typed_number)
    results.uniq { |r| r['place_id'] }.each_with_index.sort_by { |r, i|
      house_number = r.dig('address', 'house_number')
      band = if typed_number && house_number == typed_number then 0
             elsif typed_number && house_number              then 1
             elsif house_number                              then 2
             else                                                3
             end
      [band, i]
    }.map(&:first)
  end

  def nominatim_suggest(search_params)
    base  = ENV['NOMINATIM_URL'] || 'http://10.0.0.18:8088'
    query = { format: 'json', addressdetails: 1, countrycodes: 'us', limit: 5 }.merge(search_params)

    bounds = Utility.new.get_provider_bounds(current_provider)
    if bounds
      query[:viewbox] = "#{bounds[:min_lon]},#{bounds[:max_lat]},#{bounds[:max_lon]},#{bounds[:min_lat]}"
      query[:bounded] = 1
    end

    ActiveSupport::JSON.decode(
      OpenURI.open_uri("#{base}/search?#{query.to_query}", open_timeout: 3, read_timeout: 5).read
    )
  rescue StandardError => e
    Rails.logger.warn "geocode_suggest(#{search_params.keys.join(',')}) failed: #{e.class}: #{e.message}"
    []
  end

  # Completes a partial street from the local dictionary, then geocodes the
  # completed address. The dictionary supplies the prefix matching and the
  # correct street type; the geocoder still supplies the house number, so a
  # number nobody has used before still resolves.
  def street_dictionary_suggest(term)
    house_number, fragment = StreetDictionaryEntry.split_house_number(term)
    return [] if fragment.blank?

    StreetDictionaryEntry.complete(fragment).flat_map { |entry|
      street = house_number.present? ? "#{house_number} #{entry.street}" : entry.street
      nominatim_suggest(street: street, city: entry.city, state: entry.state)
    }.uniq { |r| r['place_id'] }.first(SUGGEST_LIMIT)
  end

  def parse_search_term
    term = params['term'].downcase.strip

    #clean up address
    term.gsub!(' apt ', ' #')
    term.gsub!(' apartment ', ' #')
    term.gsub!(' suite ', ' #')

    term.gsub!(' n ', ' north ')
    term.gsub!(' ne ', ' northeast ')
    term.gsub!(' e ', ' east ')
    term.gsub!(' se ', ' southeast ')
    term.gsub!(' s ', ' south ')
    term.gsub!(' sw ', ' southwest ')
    term.gsub!(' w ', ' west ')
    term.gsub!(' nw ', ' northwest ')

    term.gsub!(' ave,', 'avenue,')
    term.gsub!(' dr,', 'drive,')
    term.gsub!(' st,', 'street,')
    term.gsub!(' blvd,', 'boulevard,')
    term.gsub!(' pkwy,', 'parkway,')

    term
  end

  def process_geom
    if !params[:lat].blank? && !params[:lon].blank?
      Address.compute_geom(params[:lat], params[:lon])
    elsif !params[:address_lat].blank? && !params[:address_lon].blank?
      Address.compute_geom(params[:address_lat], params[:address_lon])
    else
      nil 
    end
  end
end
