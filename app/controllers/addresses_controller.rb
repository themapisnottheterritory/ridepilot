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

    results = nominatim_suggest(q: term)
    results = nominatim_suggest(street: term, state: NOMINATIM_FALLBACK_STATE) if results.empty?
    # Third pass: the caller may have typed a partial street ("1404 E Vir"),
    # which Nominatim cannot match at all. Runs last so it can only add
    # results, never displace ones the geocoder already found.
    results = street_dictionary_suggest(term) if results.empty?

    render json: results
  end

  private

  # Returns raw Nominatim JSON; the pickers already know how to parse that shape.
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
