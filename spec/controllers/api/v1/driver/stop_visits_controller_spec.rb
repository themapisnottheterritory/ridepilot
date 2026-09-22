require "rails_helper"

RSpec.describe Api::V1::Driver::StopVisitsController, type: :controller do
  let(:provider) { create(:provider) }
  let!(:setup)   { build_fixed_run(provider) }
  let(:run)      { setup[0] }
  let(:driver)   { setup[1] }

  before do
    user = driver.user
    user.update_column(:authentication_token, "tok-#{SecureRandom.hex(8)}") if user.authentication_token.blank?
    request.headers.merge!("X-User-Username" => user.username, "X-User-Token" => user.authentication_token)
  end

  it "records served and skipped stops, once each" do
    visits = [
      { client_uuid: "v1", external_route_id: "r1", external_stop_id: "s1", trip_id: "run_01", status: "served",
        scheduled_time: "08:00", arrived_at: "2026-09-22T08:00:10Z", departed_at: "2026-09-22T08:00:40Z", dwell_seconds: 30, deviation_seconds: 40 },
      { client_uuid: "v2", external_route_id: "r1", external_stop_id: "s2", trip_id: "run_01", status: "skipped", deviation_seconds: -90 },
    ]
    post :create, params: { id: run.id, visits: visits }
    expect(response.status).to eq 200
    expect(JSON.parse(response.body)["accepted"]).to eq 2
    post :create, params: { id: run.id, visits: visits }
    expect(JSON.parse(response.body)["accepted"]).to eq 0
    expect(JSON.parse(response.body)["total"]).to eq 2

    rows = run.fixed_route_stop_visits.order(:id)
    expect(rows.map(&:status)).to eq %w[served skipped]
    expect(rows.first.fixed_route_stop).to eq run.fixed_route.stops.first   # matched by external ids
    expect(rows.first.stop_name).to eq "Depot"
    expect(rows.first.dwell_seconds).to eq 30
    expect(rows.last.deviation_seconds).to eq(-90)

    get :index, params: { id: run.id }
    expect(JSON.parse(response.body)["visits"].size).to eq 2
  end

  it "refuses a run that is not the driver's" do
    other = Run.new(provider: provider, driver: create(:driver, provider: provider), vehicle: run.vehicle, date: Date.today, service_mode: "fixed_route", fixed_route_id: run.fixed_route_id)
    other.save!(validate: false)
    post :create, params: { id: other.id, visits: [{ client_uuid: "x", external_route_id: "r1", external_stop_id: "s1", status: "served" }] }
    expect(response.status).to eq 404
  end
end
