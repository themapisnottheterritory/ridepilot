class VehicleSerializer
  include FastJsonapi::ObjectSerializer
  set_type :vehicle
  attributes :name
end
