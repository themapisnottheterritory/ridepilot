require "rails_helper"

# Vehicles > Garages, the bus form's Garage list and the run's Change
# Locations picker. The two page templates are staged in tmp/staged until the
# deploy, so render those when present.
RSpec.describe "Garages", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:staff) { create(:role, level: Role::ADMIN_LEVEL).user }
  let(:provider) { staff.current_provider }
  before do
    staged = Rails.root.join("tmp", "staged", "views")
    ActionController::Base.prepend_view_path(staged.to_s) if staged.exist?
    sign_in staff
  end
  def garage(name, lat, lon) = GarageAddress.create!(provider: provider, name: name, address: "#{name} St", city: "Victoria", state: "TX", zip: "77901", the_geom: Address.compute_geom(lat, lon))

  it "adds a garage from a picked address, and refuses one with no pin" do
    post "/en/garages", params: { garage_address: { name: "Edna", address: "404 North Kleas Street", city: "Edna", state: "TX", zip: "77957" }, lat: "28.981922", lon: "-96.645456" }
    expect(response).to redirect_to(garages_path)
    expect(GarageAddress.named.find_by(provider: provider, name: "Edna")).to be_present
    post "/en/garages", params: { garage_address: { name: "Nowhere", address: "1 Typed St", city: "Edna", state: "TX", zip: "77957" }, lat: "", lon: "" }
    expect(response.body).to include("isn&#39;t on the map")
    get "/en/garages"
    expect(response.body).to include("Edna", "Add a garage")
  end

  it "moves a bus by picking a garage, without changing the shared garage" do
    victoria = garage("Victoria office", 28.8126, -96.9897)
    lavaca = garage("Port Lavaca yard", 28.6005, -96.6369)
    vehicle = create(:vehicle, provider: provider, garage_address: victoria)
    get "/en/vehicles/#{vehicle.id}/edit"
    expect(response.body).to include('name="garage_choice"', "Port Lavaca yard", "Other address (this bus only)")
    patch "/en/vehicles/#{vehicle.id}", params: { garage_choice: lavaca.id, vehicle: { name: vehicle.name, garage_address_attributes: { id: victoria.id, provider_id: provider.id, address: victoria.address } } }
    expect(vehicle.reload.garage_address_id).to eq lavaca.id
    expect(victoria.reload.address).to eq "Victoria office St"
    expect(flash[:notice]).to include("now lives at Port Lavaca yard")
  end

  it "gives a bus its own address instead of editing the garage it shares" do
    victoria = garage("Victoria office", 28.8126, -96.9897)
    other_bus = create(:vehicle, provider: provider, garage_address: victoria)
    vehicle = create(:vehicle, provider: provider, garage_address: victoria)
    patch "/en/vehicles/#{vehicle.id}", params: { garage_choice: "other", lat: "28.98", lon: "-96.64",
      vehicle: { name: vehicle.name, garage_address_attributes: { id: victoria.id, provider_id: provider.id, address: "9 Somewhere Rd", city: "Edna", state: "TX", zip: "77957" } } }
    expect(vehicle.reload.garage_address_id).not_to eq victoria.id
    expect(vehicle.garage_address.address).to eq "9 Somewhere Rd"
    expect(victoria.reload.address).to eq "Victoria office St"
    expect(other_bus.reload.garage_address_id).to eq victoria.id
  end

  it "picks a garage for one run's end, and moves its end stop" do
    victoria = garage("Victoria office", 28.8126, -96.9897)
    edna = garage("Edna", 28.9819, -96.6455)
    run = create(:run, provider: provider, vehicle: create(:vehicle, provider: provider, garage_address: victoria), date: Date.current + 1)
    run.reset_itineraries
    get "/en/runs/#{run.id}/request_change_locations", xhr: true
    expect(response.body).to include("to_garage_id").and include("Edna")
    patch "/en/runs/#{run.id}/update_locations", params: { to_garage_id: edna.id, from_garage_id: victoria.id, run: { name: run.name } }
    expect(run.reload.to_garage_address_id).to eq edna.id
    expect(run.itineraries.find_by(leg_flag: 3).address_id).to eq edna.id
  end
end
