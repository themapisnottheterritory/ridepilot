require 'mysql2'

class BusAvlConnection
  attr_reader :host, :database, :username, :password

  def initialize(host:, database:, username:, password:)
    @host = host
    @database = database
    @username = username
    @password = password
  end

  # Returns array of hashes with keys matching OpenTransit format:
  # { 'vehicle_id' => '1745', 'lat' => 48.123, 'lon' => -123.456,
  #   'speed' => 35.0, 'heading' => 180.0, 'timestamp' => '2026-02-18 10:30:00' }
  def fetch_locations
    client = Mysql2::Client.new(
      host: host,
      database: database,
      username: username,
      password: password,
      connect_timeout: 5,
      read_timeout: 10
    )

    # Only fetch locations updated in the last hour (active vehicles)
    results = client.query(
      "SELECT unit, lat, lon, speed, heading, date FROM last_location WHERE date >= NOW() - INTERVAL 1 HOUR",
      symbolize_keys: false
    )

    results.map do |row|
      {
        'vehicle_id' => row['unit'].to_s.strip,
        'lat' => row['lat'].to_f,
        'lon' => row['lon'].to_f,
        'speed' => row['speed'].to_f,
        'heading' => row['heading'].to_f,
        'timestamp' => row['date'].to_s
      }
    end
  ensure
    client&.close
  end
end
