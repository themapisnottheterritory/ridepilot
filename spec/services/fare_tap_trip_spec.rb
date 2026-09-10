require "rails_helper"

RSpec.describe FareTap, "#trip!" do
  let(:provider) { create(:provider) }
  let(:rider)    { create_rider(provider) }
  let!(:setup)   { build_udr_trip(provider, rider) }
  let(:trip)     { setup[0] }
  let(:driver)   { setup[2] }
  let(:token)    { FareToken.create!(provider: provider, customer: rider, kind: "rfid", uid: "04A3B2C1") }
  let(:tap)      { FareTap.new(provider: provider, driver: driver) }

  def tap!(**opts)
    tap.trip!(**{ trip: trip, uid: token.uid, client_uuid: SecureRandom.uuid }.merge(opts))
  end

  before do
    provider.update!(fare_udr_default: 1.50)
    FareLedger.new(rider, provider: provider).load!(10, payment_method: "cash")
  end

  it "debits the provider's demand-response fare and marks the trip collected" do
    r = tap!
    expect(r.fare).to eq 1.5
    expect(r.balance).to eq 8.5
    expect(r.transaction.trip).to eq trip
    trip.reload
    expect(trip.fare_collected_time).to be_present
    expect(trip.fare_amount).to eq 1.5
    expect(trip.fare.fare_type).to eq "payment"
  end

  it "prefers the amount on the trip, and an amount the driver typed over that" do
    trip.update_columns(fare_amount: 2.0)
    expect(tap!.fare).to eq 2.0
    FareTap.new(provider: provider, driver: driver).refund_trip!(trip)
    expect(tap!(amount: "3.25").fare).to eq 3.25
  end

  it "refuses someone else's card unless the driver confirms, then notes who it paid for" do
    other = create_rider(provider)
    other_token = FareToken.create!(provider: provider, customer: other, kind: "rfid", uid: "AABBCCDD")
    FareLedger.new(other, provider: provider).load!(5, payment_method: "cash")
    expect { tap!(uid: other_token.uid) }.to raise_error(FareTap::Mismatch) { |e| expect(e.message).to include(other.name).and include(rider.name) }
    expect(trip.reload.fare_collected_time).to be_nil
    r = tap!(uid: other_token.uid, confirm_mismatch: true)
    expect(r.customer).to eq other
    expect(other.reload.fare_balance).to eq 3.5
    expect(rider.reload.fare_balance).to eq 10
    expect(r.transaction.note).to include(rider.name)
  end

  it "does not charge twice: already collected, and duplicate client_uuid" do
    uuid = SecureRandom.uuid
    tap!(client_uuid: uuid)
    expect(tap!(client_uuid: uuid).duplicate).to be true
    expect { tap! }.to raise_error(FareTap::AlreadyCollected)
    expect(rider.reload.fare_balance).to eq 8.5
  end

  it "makes a pass holder's trip free but still collected" do
    rider.update!(fare_pass_expires_on: Date.current + 5)
    r = tap!
    expect(r.pass).to be true
    expect(r.fare).to eq 0
    expect(trip.reload.fare_collected_time).to be_present
    expect(rider.reload.fare_balance).to eq 10
  end

  it "refuses free and donation trips" do
    # The trip copied the provider's fare setting when it was booked.
    trip.fare.update!(fare_type: :free)
    expect { tap! }.to raise_error(FareTap::Error, /no fare/)
    trip.fare.update!(fare_type: :donation)
    expect { tap! }.to raise_error(FareTap::Error, /donation/)
  end

  it "refuses under the floor and leaves the trip uncollected" do
    FareLedger.new(rider, provider: provider).adjust!(-9, note: "test")
    expect { tap! }.to raise_error(FareTap::BelowFloor)
    expect(trip.reload.fare_collected_time).to be_nil
  end

  it "refunds and clears the mark on undo, once" do
    tap!
    tap.refund_trip!(trip)
    expect(rider.reload.fare_balance).to eq 10
    expect(trip.reload.fare_collected_time).to be_nil
    tap.refund_trip!(trip)
    expect(rider.reload.fare_balance).to eq 10
  end
end
