class RoutineMessageSerializer
  include FastJsonapi::ObjectSerializer
  set_type :routine_message

  attribute :id, :body, :driver_id, :provider_id, :sender_id, :run_id, :trip_id, :created_at

  attribute :sender_name do |object|
    object.sender.display_name if object.sender
  end

  # the trip's pickup stop on the run, so the tablet can offer "Go to stop"
  attribute :itinerary_id do |object|
    object.pickup_itinerary_id
  end
end
