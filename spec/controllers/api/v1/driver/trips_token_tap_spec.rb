require "rails_helper"

RSpec.describe Api::V1::Driver::TripsController, type: :controller do
  let(:provider) { create(:provider) }
  let(:rider)    { create_rider(provider) }
  let!(:setup)   { build_udr_trip(provider, rider) }
  let(:trip)     { setup[0] }
  let(:driver)   { setup[2] }
  let!(:token)   { FareToken.create!(provider: provider, customer: rider, kind: "rfid", uid: "04A3B2C1") }

  before do
    provider.update!(fare_udr_default: 1.50)
    FareLedger.new(rider, provider: provider).load!(5, payment_method: "cash")
    user = driver.user
    user.update_column(:authentication_token, "tok-#{SecureRandom.hex(8)}") if user.authentication_token.blank?
    request.headers.merge!("X-User-Username" => user.username, "X-User-Token" => user.authentication_token)
  end

  it "charges the trip fare to the card" do
    post :token_tap, params: { id: trip.id, uid: "04 a3 b2 c1", client_uuid: "t1" }
    expect(response.status).to eq 200
    tap = JSON.parse(response.body)["tap"]
    expect(tap["rider_name"]).to eq rider.name
    expect(tap["fare"]).to eq 1.5
    expect(tap["balance"]).to eq 3.5
    expect(tap["collected_at"]).to be_present
  end

  it "answers 409 with both names for someone else's card, then accepts the confirmation" do
    other = create_rider(provider)
    FareToken.create!(provider: provider, customer: other, kind: "rfid", uid: "AABBCCDD")
    FareLedger.new(other, provider: provider).load!(5, payment_method: "cash")
    post :token_tap, params: { id: trip.id, uid: "AABBCCDD", client_uuid: "t2" }
    expect(response.status).to eq 409
    data = JSON.parse(response.body)["data"]
    expect(data["code"]).to eq "mismatch"
    expect(data["card_rider_name"]).to eq other.name
    expect(data["trip_rider_name"]).to eq rider.name
    post :token_tap, params: { id: trip.id, uid: "AABBCCDD", client_uuid: "t2", confirm_mismatch: true }
    expect(response.status).to eq 200
    expect(JSON.parse(response.body)["tap"]["paid_for"]).to eq rider.name
  end

  it "refunds on delete" do
    post :token_tap, params: { id: trip.id, uid: "04A3B2C1", client_uuid: "t3" }
    delete :undo_token_tap, params: { id: trip.id }
    expect(response.status).to eq 200
    expect(JSON.parse(response.body)["refunded"]).to eq 1.5
    expect(rider.reload.fare_balance).to eq 5.0
    expect(trip.reload.fare_collected_time).to be_nil
  end

  it "hides trips on other drivers' runs" do
    stranger = create(:driver, provider: provider)
    stranger.user.update_column(:authentication_token, "tok-x")
    request.headers.merge!("X-User-Username" => stranger.user.username, "X-User-Token" => "tok-x")
    post :token_tap, params: { id: trip.id, uid: "04A3B2C1", client_uuid: "t4" }
    expect(response.status).to eq 404
  end
end
