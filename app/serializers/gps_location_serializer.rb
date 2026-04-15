class GpsLocationSerializer
  include FastJsonapi::ObjectSerializer
  set_type :gps_location

  attribute :latitude, :longitude, :bearing, :speed, :run_id
end
