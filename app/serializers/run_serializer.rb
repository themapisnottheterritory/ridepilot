class RunSerializer
  include FastJsonapi::ObjectSerializer
  set_type :run
  attributes :name, :complete, :start_odometer, :end_odometer, :actual_start_time, :actual_end_time, :driver_notes, :manifest_published_at, :vehicle_confirmed_at, :service_mode

  belongs_to :vehicle

  # Fixed-route runs: the route the tablet shows and logs walk-ons against.
  attribute :fixed_route do |object|
    r = object.fixed_route
    r && { id: r.id, name: r.name, display_name: r.display_name, color: r.color, kind: r.kind }
  end

  attribute :scheduled_start_time_seconds do |object|
    (object.scheduled_start_time - object.scheduled_start_time.beginning_of_day).to_i if object.scheduled_start_time
  end

  attribute :scheduled_end_time_seconds do |object|
    (object.scheduled_end_time - object.scheduled_end_time.beginning_of_day).to_i if object.scheduled_end_time
  end

  attribute :trips_count do |object|
    object.trips.size
  end

  attribute :status_code do |object|
    if object.end_odometer.present?
      2
    elsif object.start_odometer.present?
      1
    else
      0
    end
  end
end
