require "rails_helper"

# Pins to check (2026-10-03): staff move a pin to where drivers stop, keep it, or undo.
RSpec.describe PinChecksController, type: :controller do
  render_views
  login_admin_as_current_user
  let(:provider) { @current_user.current_provider }
  let(:customer) { create(:customer, provider: provider) }
  let(:home) do
    create(:address, type: "CustomerCommonAddress", provider: provider, customer_id: customer.id,
                     address: "100 Test St", city: "Victoria", the_geom: Address.compute_geom(28.80000, -97.00000))
  end
  let(:spot) { [28.80450, -96.99550] }

  before do
    3.times do |d|
      StopSighting.create!(address_id: home.id, itinerary_id: 800_000 + d, provider_id: provider.id,
                           seen_at: (d + 1).days.ago, latitude: spot[0], longitude: spot[1], dwell_secs: 80)
    end
  end

  it "lists the pin with both points" do
    get :index
    expect(response).to be_successful
    expect(response.body).to include("Pins to check", "100 Test St", "Use where drivers stop")
  end

  it "moves the pin only when someone chooses to, and records it" do
    patch :update, params: { id: home.id, decision: "moved" }
    home.reload
    expect(DriverStops.meters(home.latitude, home.longitude, *spot)).to be < 5
    check = PinCheck.last
    expect([check.decision, check.from_latitude.round(5), check.user_id]).to eq ["moved", 28.8, @current_user.id]
    get :index
    expect(response.body).not_to include("Use where drivers stop")
  end

  it "keeps the pin without moving it" do
    patch :update, params: { id: home.id, decision: "kept" }
    expect(home.reload.latitude.round(5)).to eq 28.8
    expect(PinCheck.last.decision).to eq "kept"
  end

  it "undoes a move, putting the old pin back" do
    patch :update, params: { id: home.id, decision: "moved" }
    delete :destroy, params: { id: PinCheck.last.id }
    expect(home.reload.latitude.round(5)).to eq 28.8
    expect(PinCheck.count).to eq 0
  end

  it "won't undo over a pin someone has changed since" do
    patch :update, params: { id: home.id, decision: "moved" }
    home.reload.update_column(:the_geom, Address.compute_geom(28.7, -97.1))
    delete :destroy, params: { id: PinCheck.last.id }
    expect(home.reload.latitude.round(3)).to eq 28.7
    expect(flash[:alert]).to match(/changed since/)
  end

  it "refuses a decision it doesn't know" do
    patch :update, params: { id: home.id, decision: "delete" }
    expect(home.reload.latitude.round(5)).to eq 28.8
    expect(PinCheck.count).to eq 0
  end
end
