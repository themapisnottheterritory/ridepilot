class OsrmDistanceDurationService < AbstractDistanceDurationService

  # Self-hosted OSRM backend (docker service `osrm`), the routing engine behind
  # the Leaflet map stack that replaced Google. Fall back to the docker service
  # name so a blank/misconfigured OSRM_URL still resolves in this deployment.
  OSRM_URL = ENV['OSRM_URL'].presence || 'http://osrm:5000'

  private

  # OSRM expects lon,lat order, coordinate pairs joined by ';'.
  def build_url
    coords = "#{@from_lon},#{@from_lat};#{@to_lon},#{@to_lat}"
    "#{OSRM_URL}/route/v1/driving/#{coords}?overview=false&alternatives=false&steps=false"
  end

  def parse_response(result)
    if result['code'] != 'Ok'
      Rails.logger.error "OSRM service failure: #{result['code']} #{result['message']}"
      return false, result['message']
    else
      # first route carries top-level distance (meters) + duration (seconds)
      return true, result['routes'].try(:first)
    end
  end

  # in seconds
  def parse_drive_time(response)
    response['duration'] rescue nil
  end

  # in miles
  def parse_drive_distance(response)
    (response['distance'] * METERS_TO_MILES) rescue nil
  end

  def parse_driver_dist_and_duration(response)
    {
      distance: parse_drive_distance(response),
      duration: parse_drive_time(response)
    }
  end

end
