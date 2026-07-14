class GeocodingService

  attr_reader :term, :provider

  def initialize(search_str, provider)
    @term = search_str
    @provider = provider
    nominatim_url = ENV['NOMINATIM_URL'] || 'http://10.0.0.18:8088'
    @base_url = "#{nominatim_url}/search?format=json&addressdetails=1&countrycodes=us&limit=10"
  end

  def execute
    url = @base_url + "&q=" + CGI.escape(@term)
    viewbox_str = add_search_viewbox_to_url #only addresses within one decimal degree of the district
    url += viewbox_str if viewbox_str

    result = OpenURI.open_uri(url).read

    addresses = ActiveSupport::JSON.decode(result)

    #now, convert addresses to local json format
    address_json = addresses.map { |raw_address|
      # TODO add apt numbers
      address = raw_address['address']
      street_address = '%s %s' % [address['house_number'], address['road']]
      city = address['city'] || address['town'] || address['hamlet']
      state = STATE_NAME_TO_POSTAL_ABBREVIATION[address['state'].upcase]

      address_obj = Address.new(
                  :address => street_address,
                  :city => city,
                  :state => state,
                  :zip => address['postcode'],
                  :the_geom => Address.compute_geom(raw_address['lat'], raw_address['lon'])
                  )
      next if !address_obj.valid?
      address_obj.json.merge({label: raw_address["display_name"]})

    }

    address_json.compact
  end

  private

  def add_search_viewbox_to_url
    bounds = Utility.new.get_provider_bounds(@provider)

    viewbox_str = "&viewbox=#{bounds[:min_lon]},#{bounds[:max_lat]},#{bounds[:max_lon]},#{bounds[:min_lat]}" if bounds

    viewbox_str
  end

end