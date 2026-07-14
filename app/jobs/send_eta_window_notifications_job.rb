class SendEtaWindowNotificationsJob < ApplicationJob
  queue_as :default

  def perform(date)
    date = Date.parse(date.to_s) unless date.is_a?(Date)
    tz = "Central Time (US & Canada)"

    Trip.for_date(date)
        .scheduled_to_run
        .where.not(estimated_pickup_time: nil)
        .includes(:customer, :run, :pickup_address)
        .find_each do |trip|
      next unless trip.customer&.sms_notifications_enabled? && trip.customer&.phone_number_1.present?

      eta = trip.estimated_pickup_time.in_time_zone(tz)

      SmsNotificationJob.perform_later(
        trip.customer_id,
        :eta_window,
        agency: trip.run.provider.name,
        eta_start: (eta - 10.minutes).strftime("%I:%M %p"),
        eta_end: (eta + 10.minutes).strftime("%I:%M %p"),
        pickup_address: trip.pickup_address&.address.to_s
      )
    end
  end
end
