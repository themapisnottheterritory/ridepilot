class SmsNotificationService
  TEMPLATES = {
    confirmation: {
      en: "Your %{agency} ride is confirmed. Pickup at %{pickup_time} from %{pickup_address}. Reply STOP to opt out.",
      es: "Su viaje con %{agency} esta confirmado. Recogida a las %{pickup_time} en %{pickup_address}. Responda STOP para cancelar."
    },
    reminder_day_before: {
      en: "Reminder: Your %{agency} ride is tomorrow at %{pickup_time}. Call %{phone} to cancel or change.",
      es: "Recordatorio: Su viaje con %{agency} es manana a las %{pickup_time}. Llame al %{phone} para cancelar o cambiar."
    },
    eta_window: {
      en: "Your %{agency} driver will arrive between %{eta_start} and %{eta_end}. Please be ready at %{pickup_address}.",
      es: "Su conductor de %{agency} llegara entre las %{eta_start} y las %{eta_end}. Por favor este listo en %{pickup_address}."
    },
    vehicle_approaching: {
      en: "Your %{agency} driver is %{minutes} minutes away. Vehicle: %{vehicle_description}.",
      es: "Su conductor de %{agency} esta a %{minutes} minutos. Vehiculo: %{vehicle_description}."
    },
    schedule_change: {
      en: "Schedule update: Your pickup time has changed to %{new_time}. Questions? Call %{phone}.",
      es: "Actualizacion: Su hora de recogida cambio a %{new_time}. Preguntas? Llame al %{phone}."
    },
    trip_cancelled: {
      en: "Your %{agency} trip for %{date} has been cancelled. Call %{phone} to reschedule.",
      es: "Su viaje con %{agency} para el %{date} fue cancelado. Llame al %{phone} para reprogramar."
    }
  }.freeze

  def self.send_notification(customer:, template:, **vars)
    return unless sms_enabled?
    return unless customer.try(:sms_notifications_enabled?) && customer.phone_number_1.present?

    lang = customer.try(:preferred_language).to_s.to_sym
    lang = :en unless TEMPLATES[template]&.key?(lang)
    body = format(TEMPLATES[template][lang], **vars)
    number = normalize_phone(customer.phone_number_1)

    client.messages.create(from: from_number, to: number, body: body)
  rescue => e
    Rails.logger.error("SMS failed for customer #{customer.id}: #{e.message}")
  end

  def self.normalize_phone(raw)
    digits = raw.to_s.gsub(/\D/, "")
    digits.length == 10 ? "+1#{digits}" : "+#{digits}"
  end

  def self.sms_enabled?
    ENV["TWILIO_ACCOUNT_SID"].present? && ENV["TWILIO_AUTH_TOKEN"].present?
  end

  def self.client
    @client ||= Twilio::REST::Client.new(
      ENV["TWILIO_ACCOUNT_SID"],
      ENV["TWILIO_AUTH_TOKEN"]
    )
  end

  def self.send_portal_link(customer, trip)
    return unless sms_enabled?
    return unless customer.phone_number_1.present?

    auth = CustomerAuth.generate_for(customer)
    url = Rails.application.routes.url_helpers.client_portal_url(
      token: auth.token,
      host: ENV.fetch("APP_HOST", "localhost:3000")
    )

    lang = customer.try(:preferred_language).to_s.to_sym
    body = if lang == :es
             "Siga su viaje con #{trip.provider.name}: #{url}"
           else
             "Track your #{trip.provider.name} ride: #{url}"
           end

    number = normalize_phone(customer.phone_number_1)
    client.messages.create(from: from_number, to: number, body: body)
  rescue => e
    Rails.logger.error("Portal link SMS failed for customer #{customer.id}: #{e.message}")
  end

  def self.from_number
    ENV.fetch("TWILIO_FROM_NUMBER", "+10000000000")
  end
end
