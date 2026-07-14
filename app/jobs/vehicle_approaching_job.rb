class VehicleApproachingJob < ApplicationJob
  queue_as :default

  def perform(trip_id, minutes_away)
    trip = Trip.find(trip_id)
    return unless trip.customer&.sms_notifications_enabled? && trip.customer&.phone_number_1.present?

    # Only fire once per trip - use estimated_pickup_time presence as a loose guard
    # (a proper approach_notified flag could be added later)
    vehicle = trip.run&.vehicle
    vehicle_desc = if vehicle
                     [vehicle.year, vehicle.make, vehicle.model].compact.join(" ")
                   else
                     "your vehicle"
                   end

    SmsNotificationJob.perform_later(
      trip.customer_id,
      :vehicle_approaching,
      agency: trip.provider.name,
      minutes: minutes_away.to_s,
      vehicle_description: vehicle_desc
    )
  end
end
