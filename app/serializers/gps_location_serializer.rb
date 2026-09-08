class GpsLocationSerializer
  include FastJsonapi::ObjectSerializer
  set_type :gps_location

  attribute :latitude, :longitude, :bearing, :speed, :run_id

  # Fixed-route runs: the car icon on the CAD map takes the route colour.
  attribute :route_color do |object|
    object.run.try(:fixed_route).try(:css_color)
  end
end
