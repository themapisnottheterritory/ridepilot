class DayBeforeReminderJob < ApplicationJob
  queue_as :default

  def perform(date = Date.tomorrow)
    Trip.for_date(date).scheduled_to_run.includes(:customer, :provider, :pickup_address).each do |trip|
      next unless trip.customer&.sms_notifications_enabled? && trip.customer&.phone_number_1.present?

      SmsNotificationJob.perform_later(
        trip.customer_id,
        :reminder_day_before,
        agency: trip.provider.name,
        pickup_time: trip.pickup_time.in_time_zone("Central Time (US & Canada)").strftime("%I:%M %p"),
        phone: trip.provider.phone_number
      )
    end
  end
end
