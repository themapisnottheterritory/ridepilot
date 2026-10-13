require "rails_helper"

# Bus cards (2026-10-13): a laminated QR per bus that the tablet scans at the
# start of a run; printed from the Vehicle page, or all at once from Vehicles.
RSpec.describe "Bus cards", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:admin) { create(:super_admin) }
  let(:provider) { admin.current_provider }
  let!(:bus) { create(:vehicle, name: "1777", provider: provider) }
  let!(:renamed) { create(:vehicle, name: "2457 (R7)", provider: provider) }
  before { sign_in admin }

  it "codes each bus by its id, and reads a scanned card back" do
    expect(bus.bus_card_code).to eq "GCRPC-BUS:#{bus.id}"
    expect(Vehicle.from_bus_card(" gcrpc-bus:#{bus.id} ")).to eq bus
    expect(Vehicle.from_bus_card("GCRPC-BUS:999999")).to be_nil
    expect(Vehicle.from_bus_card("04A3B2C1")).to be_nil      # a fare card is not a bus card
  end

  it "prints one bus's card from its page" do
    get "/en/vehicles/#{bus.id}"
    expect(response.body).to include("Print bus card", "/en/vehicles/#{bus.id}/bus_card")
    get "/en/vehicles/#{bus.id}/bus_card"
    expect(response.status).to eq 200
    expect(response.body).to include("1777", "GCRPC-BUS:#{bus.id}", "<svg").and include("1 bus card ")
    expect(response.body).not_to include("2457 (R7)")
  end

  it "prints every active bus of the agency from the list" do
    renamed.update_column(:active, true)
    get "/en/vehicles"
    expect(response.body).to include("Print all bus cards")
    get "/en/vehicles/bus_cards"
    expect(response.status).to eq 200
    expect(response.body).to include("GCRPC-BUS:#{bus.id}", "GCRPC-BUS:#{renamed.id}", "2457 (R7)")
  end
end
