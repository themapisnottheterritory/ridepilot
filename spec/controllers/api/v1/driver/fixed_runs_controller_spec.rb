require "rails_helper"

# GCRPC Driver opens today's fixed run for a GTFS route before it taps cards.
RSpec.describe Api::V1::Driver::FixedRunsController, type: :controller do
  let(:provider) { create(:provider) }
  let!(:setup)   { build_fixed_run(provider) }
  let(:existing) { setup[0] }
  let(:driver)   { setup[1] }
  let(:route)    { setup[2] }

  before do
    route.update!(external_route_ids: ["r1", "r1-south"])
    user = driver.user
    user.update_column(:authentication_token, "tok-#{SecureRandom.hex(8)}") if user.authentication_token.blank?
    request.headers.merge!("X-User-Username" => user.username, "X-User-Token" => user.authentication_token)
  end

  it "returns today's existing run for the route, with stops and categories" do
    post :open, params: { external_route_id: "r1-south", vehicle: existing.vehicle.name }
    expect(response.status).to eq 200
    body = JSON.parse(response.body)
    expect(body["run_id"]).to eq existing.id
    expect(body["created"]).to be false
    expect(body["stops"].map { |s| s["external_stop_id"] }).to eq %w[s1 s2]
    expect(body["rider_categories"].map { |c| c["name"] }).to include "Adult"
    expect(body["fare_types"].map { |c| c["name"] }).to include "Cash"
    expect(body["totals"]["boarded"]).to eq 0
  end

  it "creates the run when there is none, once" do
    existing.really_destroy! rescue existing.destroy
    post :open, params: { external_route_id: "r1", scheduled_start: "08:00", run_name: "Red · 08:00" }
    expect(response.status).to eq 200
    first = JSON.parse(response.body)
    expect(first["created"]).to be true
    run = Run.find(first["run_id"])
    expect(run.fixed_route).to eq route
    expect(run.driver).to eq driver
    expect(run.service_mode).to eq "fixed_route"
    expect(run.scheduled_start_time.strftime("%H:%M")).to eq "08:00"
    expect(run.actual_start_time).to be_nil          # the pre-trip inspection starts it
    expect(first["started"]).to be false
    expect(first["pre_inspection_done"]).to be false

    post :open, params: { external_route_id: "r1" }
    expect(JSON.parse(response.body)["run_id"]).to eq run.id
    expect(JSON.parse(response.body)["created"]).to be false
  end

  it "gives a new run after today's has been ended" do
    existing.update_columns(actual_end_time: Time.current, end_odometer: 100, start_odometer: 90)
    post :open, params: { external_route_id: "r1" }
    body = JSON.parse(response.body)
    expect(body["run_id"]).not_to eq existing.id
    expect(body["created"]).to be true
  end

  it "rejects a route RidePilot does not know" do
    post :open, params: { external_route_id: "nope" }
    expect(response.status).to eq 404
    expect(JSON.parse(response.body)["data"]["code"]).to eq "unknown_route"
  end

  it "then accepts taps on that run" do
    rider = create_rider(provider)
    FareToken.create!(provider: provider, customer: rider, kind: "rfid", uid: "04A3B2C1", serial: "12")
    FareLedger.new(rider, provider: provider).load!(5, payment_method: "cash")
    post :open, params: { external_route_id: "r1" }
    run_id = JSON.parse(response.body)["run_id"]
    @controller = Api::V1::Driver::TokenTapsController.new
    post :create, params: { id: run_id, uid: "04A3B2C1", client_uuid: "u9", stop_name: "Depot", direction: "East" }
    expect(response.status).to eq 200
    expect(JSON.parse(response.body)["totals"]["boarded"]).to eq 1
  end
end

# A one-bus day: the driver's run is the combo route's (Gold+Green) while the
# tablet, driving Gold's loop, sends Gold's GTFS id.
RSpec.describe Api::V1::Driver::FixedRunsController, "combo route", type: :controller do
  let(:provider) { create(:provider) }
  let!(:setup)   { build_fixed_run(provider) }
  let(:driver)   { setup[1] }
  let(:gold)     { setup[2].tap { |r| r.update!(name: "Gold", external_route_ids: ["gold-n"]) } }
  let!(:green) do
    g = FixedRoute.create!(provider: provider, name: "Green", kind: "city", color: "00AA00", external_route_ids: ["green-e"])
    FixedRouteStop.create!(fixed_route: g, external_route_id: "green-e", external_stop_id: "g1", direction: "East", sequence: 1, name: "HEB")
    g
  end
  let!(:combo)   { gold; FixedRoute.rebuild_combos!(provider).first }

  before do
    setup[0].destroy
    user = driver.user
    user.update_column(:authentication_token, "tok-#{SecureRandom.hex(8)}") if user.authentication_token.blank?
    request.headers.merge!("X-User-Username" => user.username, "X-User-Token" => user.authentication_token)
  end

  it "builds the combo from its parts and gives it no stops of its own" do
    expect(combo.name).to eq "Gold+Green"
    expect(combo.external_route_ids).to eq ["gold-n", "green-e"]
    expect(combo.stops).to be_empty
    expect(combo.operating_stops.map(&:external_stop_id)).to eq %w[s1 s2 g1]
  end

  it "finds the driver's combo run from a part's GTFS id and serves both routes' stops" do
    run = Run.create!(provider: provider, name: "Gold+Green", date: Time.zone.today, service_mode: "fixed_route",
                      fixed_route: combo, driver: driver, vehicle: setup[0].vehicle)
    post :open, params: { external_route_id: "gold-n" }
    body = JSON.parse(response.body)
    expect([body["run_id"], body["created"]]).to eq [run.id, false]
    expect(body["stops"].map { |s| s["external_stop_id"] }).to eq %w[s1 s2 g1]
  end

  it "opens the part route, never the combo, when the driver has no run" do
    post :open, params: { external_route_id: "green-e" }
    body = JSON.parse(response.body)
    expect(body["created"]).to be true
    expect(Run.find(body["run_id"]).fixed_route).to eq green
  end

  it "credits a tap on a combo run to the stop's own route" do
    run = Run.create!(provider: provider, name: "Gold+Green", date: Time.zone.today, service_mode: "fixed_route",
                      fixed_route: combo, driver: driver, vehicle: setup[0].vehicle)
    heb = green.stops.first
    @controller = Api::V1::Driver::BoardingsController.new
    post :create, params: { id: run.id, stop_id: heb.id, client_uuid: "c1", entries: [{ rider_category_id: RiderCategory.first.id, boarded_count: 2 }] }
    expect(response.status).to eq 200
    expect(FixedRouteBoarding.where(run_id: run.id).pluck(:fixed_route_id).uniq).to eq [green.id]
  end
end

RSpec.describe Api::V1::Driver::FixedRunsController, "today", type: :controller do
  let(:provider) { create(:provider) }
  let!(:setup)   { build_fixed_run(provider) }
  let(:run)      { setup[0] }
  let(:driver)   { setup[1] }

  before do
    setup[2].update!(external_route_ids: ["r1", "r1-south"])
    run.update_columns(scheduled_start_time: Time.zone.parse("07:30"))
    user = driver.user
    user.update_column(:authentication_token, "tok-#{SecureRandom.hex(8)}") if user.authentication_token.blank?
    request.headers.merge!("X-User-Username" => user.username, "X-User-Token" => user.authentication_token)
  end

  it "lists what dispatch scheduled for this driver today, with the GTFS ids and the bus" do
    get :today
    body = JSON.parse(response.body)["runs"]
    expect(body.size).to eq 1
    expect(body[0]["run_id"]).to eq run.id
    expect(body[0]["external_route_ids"]).to eq %w[r1 r1-south]
    expect(body[0]["vehicle"]).to eq run.vehicle.name
    expect(body[0]["scheduled_start"]).to eq "07:30"
    expect(body[0]["started"]).to be false
  end
end
