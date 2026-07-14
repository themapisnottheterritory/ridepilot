class TwilioSmsController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :verify_authenticity_token
  skip_before_action :get_providers

  def inbound
    body = params[:Body].to_s.strip.upcase
    from = params[:From]

    if body == "STOP"
      # Find customer by phone number and opt them out
      phone_digits = from.to_s.gsub(/\D/, "").last(10)
      customers = Customer.where("REPLACE(REPLACE(phone_number_1, '-', ''), ' ', '') LIKE ?", "%#{phone_digits}")
      customers.update_all(sms_notifications_enabled: false)
    end

    head :ok
  end
end
