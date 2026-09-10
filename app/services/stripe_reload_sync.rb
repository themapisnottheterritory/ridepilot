# Online reloads without anything inbound (docs/fare-card-design.md, 6.3).
#
# The office publishes a Stripe Payment Link with one custom text field,
# "Fare card number", where the rider types the serial printed on their card.
# This job runs from cron inside the network, pulls the paid Checkout
# Sessions of the last few days, and posts one load per session. It is
# idempotent on the session id, so re-scanning the same window is harmless
# and no state has to be kept between runs.
#
#   StripeReloadSync.new(provider: Provider.find(1)).run!
#   rake fare_cards:sync_online_reloads PROVIDER_ID=1
#
# Needs STRIPE_SECRET_KEY in the app environment (docker/.env). A session
# whose card number matches nothing is reported, not posted; the office
# finds the rider from the receipt email and loads it by hand.
class StripeReloadSync
  Outcome = Struct.new(:posted, :already, :unmatched, keyword_init: true) do
    def summary
      "posted #{posted.size}, already #{already.size}, unmatched #{unmatched.size}"
    end
  end

  FIELD_KEY = /card|serial|fare/i

  attr_reader :provider

  def initialize(provider:, api_key: ENV["STRIPE_SECRET_KEY"], since: 7.days.ago, client: nil, by: nil)
    @provider = provider
    @api_key = api_key
    @since = since
    @client = client
    @by = by
  end

  def configured?
    @api_key.present?
  end

  def run!
    raise ArgumentError, "STRIPE_SECRET_KEY is not set" unless configured? || @client
    outcome = Outcome.new(posted: [], already: [], unmatched: [])
    each_paid_session do |session|
      serial = card_number_from(session)
      token = serial && FareToken.for_provider(provider.id).where(serial: serial).order(Arel.sql("CASE status WHEN 'active' THEN 0 ELSE 1 END"), :id).first
      amount = session_amount(session)
      if token.nil? || amount <= 0
        outcome.unmatched << { session: session.id, card_number: serial, amount: amount, email: email_of(session), created: Time.zone.at(session.created) }
        next
      end
      uuid = "stripe-#{session.id}"
      if FareTransaction.exists?(client_uuid: uuid)
        outcome.already << session.id
        next
      end
      FareLedger.new(token.customer, by: @by, provider: provider).load!(
        amount, payment_method: "card_online", reference: session.id, token: token,
        note: "Online reload#{email_of(session) ? " (#{email_of(session)})" : ''}",
        client_uuid: uuid, recorded_at: Time.zone.at(session.created)
      )
      outcome.posted << { session: session.id, customer: token.customer.name, amount: amount }
    end
    outcome
  end

  private

  def sessions_api
    @client || begin
      Stripe.api_key = @api_key
      Stripe::Checkout::Session
    end
  end

  def each_paid_session(&block)
    list = sessions_api.list(status: "complete", created: { gte: @since.to_i }, limit: 100)
    list.auto_paging_each do |s|
      next unless s.respond_to?(:payment_status) ? s.payment_status == "paid" : true
      block.call(s)
    end
  end

  def card_number_from(session)
    fields = Array(session.try(:custom_fields))
    field = fields.find { |f| (f.try(:key).to_s =~ FIELD_KEY) || (f.try(:label)&.try(:custom).to_s =~ FIELD_KEY) }
    value = field&.try(:text)&.try(:value) || field&.try(:numeric)&.try(:value)
    value ||= session.try(:client_reference_id)
    value.to_s.strip.sub(/\A#/, "").presence
  end

  def session_amount(session)
    cents = session.try(:amount_total).to_i
    return 0 if cents <= 0 || (session.try(:currency).to_s.presence || "usd") != "usd"
    (BigDecimal(cents) / 100).round(2)
  end

  def email_of(session)
    session.try(:customer_details)&.try(:email) || session.try(:customer_email)
  end
end
