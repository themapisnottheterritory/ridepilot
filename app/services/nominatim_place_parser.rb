class NominatimPlaceParser

  attr_reader :raw_data

  def initialize(raw_data)
    @raw_data = raw_data.deep_symbolize_keys
  end

  def parse
    {
      address: @raw_data[:address],
      city: @raw_data[:city],
      state: @raw_data[:state],
      zip: @raw_data[:zip],
      the_geom: parse_geom
    }
  rescue => e
    Rails.logger.error "NominatimPlaceParser error: #{e.message}"
    nil
  end

  private

  def parse_geom
    lat = @raw_data[:lat].to_f
    lon = @raw_data[:lon].to_f
    Address.compute_geom(lat, lon) if lat != 0 && lon != 0
  end

end
