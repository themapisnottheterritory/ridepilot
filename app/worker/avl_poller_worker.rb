class AvlPollerWorker
  include Sidekiq::Worker
  sidekiq_options queue: 'default', retry: 3

  AVL_SOURCE_OPENTRANSIT = 'opentransit_api'.freeze
  AVL_SOURCE_MYSQL       = 'mysql_direct'.freeze

  def perform
    # Include providers using either source
    providers = Provider.where(use_external_avl: true)

    providers.find_each do |provider|
      poll_provider(provider)
    rescue => e
      Rails.logger.error "AvlPollerWorker: Error polling provider #{provider.id} (#{provider.name}): #{e.message}"
    end

    # Re-enqueue self after the configured interval
    interval = ApplicationSetting.opentransit_polling_interval_seconds || 15
    AvlPollerWorker.perform_in(interval.seconds) if providers.any?
  end

  private

  def poll_provider(provider)
    # Branch based on AVL source -- like #ifdef in C
    vehicle_locations = case provider.avl_source
                        when AVL_SOURCE_MYSQL
                          fetch_from_mysql(provider)
                        else # AVL_SOURCE_OPENTRANSIT (default)
                          fetch_from_opentransit(provider)
                        end

    return if vehicle_locations.blank?

    # Build lookup: unit_id (vehicle name) -> vehicle record
    provider_vehicles = provider.vehicles.where.not(name: [nil, '']).index_by { |v| v.name.strip }

    vehicle_locations.each do |vehicle_data|
      process_vehicle_location(provider, provider_vehicles, vehicle_data)
    rescue => e
      Rails.logger.error "AvlPollerWorker: Error processing vehicle data: #{e.message}"
    end
  end

  # --- Source: OpenTransit REST API ---

  def fetch_from_opentransit(provider)
    return nil if provider.opentransit_url.blank?

    api_url = provider.opentransit_url.chomp('/')
    response = fetch_vehicles_http(api_url)
    return nil unless response

    vehicles = JSON.parse(response)
    vehicles.is_a?(Array) ? vehicles : nil
  end

  def fetch_vehicles_http(api_url)
    uri = URI("#{api_url}/api/vehicles")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 5
    http.read_timeout = 10
    http.use_ssl = (uri.scheme == 'https')

    request = Net::HTTP::Get.new(uri)
    response = http.request(request)

    if response.code.to_i == 200
      response.body
    else
      Rails.logger.warn "AvlPollerWorker: OpenTransit API returned #{response.code} from #{api_url}"
      nil
    end
  rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED => e
    Rails.logger.warn "AvlPollerWorker: Cannot reach OpenTransit at #{api_url}: #{e.message}"
    nil
  end

  # --- Source: MySQL direct (busavl.last_location) ---

  def fetch_from_mysql(provider)
    return nil if provider.busavl_host.blank?

    connection = BusAvlConnection.new(
      host:     provider.busavl_host,
      database: provider.busavl_database.presence || 'busavl',
      username: provider.busavl_username.presence || 'dbmojo',
      password: provider.busavl_password.presence || 'igotmojo'
    )

    connection.fetch_locations
  rescue => e
    Rails.logger.warn "AvlPollerWorker: Cannot read MySQL AVL from #{provider.busavl_host}: #{e.message}"
    nil
  end

  # --- Shared: process a single vehicle location record ---

  def process_vehicle_location(provider, provider_vehicles, vehicle_data)
    unit_id = vehicle_data['vehicle_id'].to_s.strip
    return if unit_id.blank?

    vehicle = provider_vehicles[unit_id]
    return unless vehicle

    lat = vehicle_data['lat'].to_f
    lon = vehicle_data['lon'].to_f
    return if lat == 0.0 && lon == 0.0

    # Find a run for this vehicle today
    # TODO: Re-add start_odometer requirement once drivers are consistently
    #       starting runs. Original filter was:
    #         .where.not(start_odometer: nil).where(end_odometer: nil)
    #       This ensured GPS only flowed for driver-started, incomplete runs.
    active_run = Run.where(
      vehicle_id: vehicle.id,
      date: Date.today,
      provider_id: provider.id
    ).where(end_odometer: nil).first

    return unless active_run

    # Parse timestamp
    log_time = if vehicle_data['timestamp'].present?
                 Time.parse(vehicle_data['timestamp'])
               else
                 Time.current
               end

    # Skip if we already have a location at this timestamp for this run
    existing = GpsLocation.where(run_id: active_run.id)
                          .where("log_time >= ?", log_time - 2.seconds)
                          .exists?
    return if existing

    GpsLocation.create!(
      latitude: lat,
      longitude: lon,
      bearing: vehicle_data['heading'].to_f,
      speed: vehicle_data['speed'].to_f,
      log_time: log_time,
      provider_id: provider.id,
      run_id: active_run.id
    )
  end
end
