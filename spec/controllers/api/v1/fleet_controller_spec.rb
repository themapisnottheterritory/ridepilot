require "rails_helper"

RSpec.describe Api::V1::FleetController, type: :controller do
  let(:provider) { create(:provider) }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("FLEET_SYNC_TOKEN").and_return("secret-token")
    v = build(:vehicle, provider: provider, name: "1733", make: "Ford", model: "E450 Eldorado Aerotech 240", year: 2019, wheelchair_lift: true, mobility_device_accommodations: 2)
    v.save!(validate: false)
    w = build(:vehicle, provider: provider, name: "1700", make: "Chevrolet", model: "Tahoe", year: 2020, active: false)
    w.save!(validate: false)
  end

  it "refuses without the token" do
    get :index, params: { provider_id: provider.id }
    expect(response.status).to eq 401
    request.headers["X-Fleet-Token"] = "wrong"
    get :index, params: { provider_id: provider.id }
    expect(response.status).to eq 401
  end

  it "lists the provider's vehicles with the lift flag" do
    request.headers["X-Fleet-Token"] = "secret-token"
    get :index, params: { provider_id: provider.id }
    expect(response.status).to eq 200
    body = JSON.parse(response.body)
    units = body["vehicles"].index_by { |v| v["unit"] }
    expect(units.keys).to match_array(%w[1700 1733])
    expect(units["1733"]["wheelchair_lift"]).to be true
    expect(units["1733"]["tie_downs"]).to eq 2
    expect(units["1733"]["model"]).to eq "E450 Eldorado Aerotech 240"
    expect(units["1700"]["wheelchair_lift"]).to be false
    expect(units["1700"]["active"]).to be false
  end
end
