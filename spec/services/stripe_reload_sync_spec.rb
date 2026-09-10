require "rails_helper"

# Stand-in for Stripe::Checkout::Session so the job runs without a key.
class FakeStripeSessions
  Field = Struct.new(:key, :label, :text, :numeric, keyword_init: true)
  Text  = Struct.new(:value)
  Session = Struct.new(:id, :status, :payment_status, :amount_total, :currency, :created, :custom_fields, :client_reference_id, :customer_details, :customer_email, keyword_init: true)
  Details = Struct.new(:email)
  List = Struct.new(:items) do
    def auto_paging_each(&b) items.each(&b); end
  end

  attr_reader :sessions, :last_params
  def initialize(sessions) @sessions = sessions; end
  def list(params) @last_params = params; List.new(sessions); end

  def self.paid(id, amount_cents, card_number, email: "rider@example.com", created: Time.current)
    Session.new(id: id, status: "complete", payment_status: "paid", amount_total: amount_cents, currency: "usd", created: created.to_i,
                custom_fields: [Field.new(key: "fare_card_number", label: nil, text: Text.new(card_number), numeric: nil)],
                client_reference_id: nil, customer_details: Details.new(email), customer_email: nil)
  end
end

RSpec.describe StripeReloadSync do
  let(:provider) { create(:provider) }
  let(:rider)    { create_rider(provider) }
  let!(:token)   { FareToken.create!(provider: provider, customer: rider, kind: "rfid", uid: "04A3B2C1", serial: "1042") }

  it "posts one card_online load per paid session and is idempotent" do
    client = FakeStripeSessions.new([FakeStripeSessions.paid("cs_1", 2000, "#1042"), FakeStripeSessions.paid("cs_2", 1000, "1042")])
    sync = StripeReloadSync.new(provider: provider, client: client)
    out = sync.run!
    expect(out.posted.size).to eq 2
    expect(rider.reload.fare_balance).to eq 30
    tx = rider.fare_transactions.find_by(reference: "cs_1")
    expect(tx.payment_method).to eq "card_online"
    expect(tx.client_uuid).to eq "stripe-cs_1"
    expect(tx.note).to include("rider@example.com")

    again = sync.run!
    expect(again.posted).to be_empty
    expect(again.already).to match_array(%w[cs_1 cs_2])
    expect(rider.reload.fare_balance).to eq 30
  end

  it "reports a card number nobody has, and skips unpaid sessions" do
    unpaid = FakeStripeSessions.paid("cs_9", 1000, "1042"); unpaid.payment_status = "unpaid"
    client = FakeStripeSessions.new([FakeStripeSessions.paid("cs_3", 1500, "9999"), unpaid])
    out = StripeReloadSync.new(provider: provider, client: client).run!
    expect(out.posted).to be_empty
    expect(out.unmatched.size).to eq 1
    expect(out.unmatched.first[:card_number]).to eq "9999"
    expect(out.unmatched.first[:amount]).to eq 15
    expect(rider.reload.fare_balance).to eq 0
  end

  it "asks Stripe only for completed sessions since the window start" do
    client = FakeStripeSessions.new([])
    StripeReloadSync.new(provider: provider, client: client, since: Time.zone.parse("2026-09-01 00:00")).run!
    expect(client.last_params[:status]).to eq "complete"
    expect(client.last_params[:created][:gte]).to eq Time.zone.parse("2026-09-01 00:00").to_i
  end

  it "refuses to run without a key or a client" do
    expect { StripeReloadSync.new(provider: provider, api_key: nil).run! }.to raise_error(ArgumentError)
  end
end
