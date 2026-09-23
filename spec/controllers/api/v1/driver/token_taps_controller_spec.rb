require "rails_helper"

RSpec.describe Api::V1::Driver::TokenTapsController, type: :controller do
  let(:provider) { create(:provider) }
  let!(:setup)   { build_fixed_run(provider) }
  let(:run)      { setup[0] }
  let(:driver)   { setup[1] }
  let(:rider)    { create_rider(provider) }
  let!(:token)   { FareToken.create!(provider: provider, customer: rider, kind: "rfid", uid: "04A3B2C1", serial: "12") }

  before do
    FareLedger.new(rider, provider: provider).load!(5, payment_method: "cash")
    user = driver.user
    user.update_column(:authentication_token, "tok-#{SecureRandom.hex(8)}") if user.authentication_token.blank?
    request.headers.merge!("X-User-Username" => user.username, "X-User-Token" => user.authentication_token)
  end

  it "charges a tap and echoes the walk-on" do
    post :create, params: { id: run.id, uid: "04 a3 b2 c1", client_uuid: "u1", stop_id: run.fixed_route.stops.first.id }
    expect(response.status).to eq 200
    body = JSON.parse(response.body)
    expect(body["tap"]["rider_name"]).to eq rider.name
    expect(body["tap"]["fare"]).to eq 1.0
    expect(body["tap"]["balance"]).to eq 4.0
    expect(body["submissions"].size).to eq 1
    expect(body["submissions"][0]["tapped"]).to be true
    expect(body["submissions"][0]["rider_name"]).to eq rider.name
  end

  it "credits a tap at another route's stop to that route (one bus driving two routes)" do
    green = FixedRoute.create!(provider: provider, name: "Green", color: "38A700", external_route_ids: ["g1"])
    walmart = FixedRouteStop.create!(fixed_route: green, external_route_id: "g1", external_stop_id: "walmart", direction: "East", sequence: 3, name: "South Walmart")
    post :create, params: { id: run.id, uid: "04A3B2C1", client_uuid: "u5", external_route_id: "g1", external_stop_id: "walmart" }
    expect(response.status).to eq 200
    row = run.fixed_route_boardings.find_by(client_uuid: "u5")
    expect(row.fixed_route).to eq green
    expect(row.stop).to eq walmart
    expect(row.stop_name).to eq "South Walmart"
    expect(row.direction).to eq "East"
  end

  it "reports an unknown card with a 404 and the normalised uid" do
    post :create, params: { id: run.id, uid: "de:ad:be:ef", client_uuid: "u2" }
    expect(response.status).to eq 404
    body = JSON.parse(response.body)
    expect(body["data"]["code"]).to eq "unknown_token"
    expect(body["data"]["uid"]).to eq "DEADBEEF"
  end

  it "reports a short balance with the numbers the driver needs" do
    FareLedger.new(rider, provider: provider).adjust!(-4.5, note: "test")
    post :create, params: { id: run.id, uid: "04A3B2C1", client_uuid: "u3" }
    expect(response.status).to eq 422
    body = JSON.parse(response.body)["data"]
    expect(body["code"]).to eq "below_floor"
    expect(body["balance"]).to eq 0.5
    expect(body["fare"]).to eq 1.0
  end

  it "serves the offline snapshot" do
    get :index, params: { id: run.id }
    expect(response.status).to eq 200
    body = JSON.parse(response.body)
    t = body["tokens"].find { |x| x["uid"] == "04A3B2C1" }
    expect(t["rider_name"]).to eq rider.name
    expect(t["balance"]).to eq 5.0
    expect(t["fare"]).to eq 1.0
    expect(body["transfer_window_minutes"]).to eq 90
  end
end

RSpec.describe Api::V1::Driver::BoardingsController, type: :controller do
  let(:provider) { create(:provider) }
  let!(:setup)   { build_fixed_run(provider) }
  let(:run)      { setup[0] }
  let(:driver)   { setup[1] }
  let(:rider)    { create_rider(provider) }
  let!(:token)   { FareToken.create!(provider: provider, customer: rider, kind: "rfid", uid: "04A3B2C1") }

  before do
    FareLedger.new(rider, provider: provider).load!(5, payment_method: "cash")
    user = driver.user
    user.update_column(:authentication_token, "tok-#{SecureRandom.hex(8)}") if user.authentication_token.blank?
    request.headers.merge!("X-User-Username" => user.username, "X-User-Token" => user.authentication_token)
  end

  it "credits a walk-on at another route's stop to that route, and an unknown stop to the run's route" do
    green = FixedRoute.create!(provider: provider, name: "Green", color: "38A700", external_route_ids: ["g1"])
    walmart = FixedRouteStop.create!(fixed_route: green, external_route_id: "g1", external_stop_id: "walmart", direction: "East", sequence: 3, name: "South Walmart")
    adult = RiderCategory.find_by!(name: "Adult")
    post :create, params: { id: run.id, client_uuid: "w1", external_route_id: "g1", external_stop_id: "walmart",
                            entries: [{ rider_category_id: adult.id, boarded_count: 2 }] }
    expect(response.status).to eq 200
    row = run.fixed_route_boardings.find_by(client_uuid: "w1")
    expect(row.fixed_route).to eq green
    expect(row.stop).to eq walmart
    expect(row.boarded_count).to eq 2

    # The route is known but the stop is not (a stop added in the authoring
    # tool and not yet synced): still Green's ridership, no stop row.
    post :create, params: { id: run.id, client_uuid: "w2", external_route_id: "g1", external_stop_id: "brand-new", stop_name: "New stop",
                            entries: [{ rider_category_id: adult.id, boarded_count: 1 }] }
    row = run.fixed_route_boardings.find_by(client_uuid: "w2")
    expect(row.fixed_route).to eq green
    expect(row.stop).to be_nil
    expect(row.stop_name).to eq "New stop"

    # Nothing recognisable: the run's own route, as before.
    post :create, params: { id: run.id, client_uuid: "w3", external_route_id: "nope", external_stop_id: "x",
                            entries: [{ rider_category_id: adult.id, boarded_count: 1 }] }
    expect(run.fixed_route_boardings.find_by(client_uuid: "w3").fixed_route).to eq run.fixed_route
  end

  it "refunds the fare when a tapped walk-on is undone" do
    FareTap.new(provider: provider, driver: driver).fixed_route!(run: run, uid: "04A3B2C1", client_uuid: "u9")
    expect(rider.reload.fare_balance).to eq 4.0
    delete :destroy, params: { id: "u9" }
    expect(response.status).to eq 200
    expect(rider.reload.fare_balance).to eq 5.0
    expect(run.fixed_route_boardings.count).to eq 0
  end
end
