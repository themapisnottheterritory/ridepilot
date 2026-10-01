require "rails_helper"

# A stop dispatch removed while the tablet still had it open: the tablet asks
# for it by id and must get a 404, not a 500 (seen 2026-10-01, run UDR3).
RSpec.describe Api::V1::Driver::ItinerariesController, type: :controller do
  let(:driver) { create(:driver) }
  let(:run)    { create(:run, driver: driver, provider: driver.provider) }
  let(:itin)   { create(:itinerary, run: run) }

  before do
    user = driver.user
    user.update_column(:authentication_token, "tok-#{SecureRandom.hex(8)}") if user.authentication_token.blank?
    request.headers.merge!("X-User-Username" => user.username, "X-User-Token" => user.authentication_token)
  end

  it "shows a stop that is on the run" do
    get :show, params: { id: itin.id }
    expect(response.status).to eq 200
  end

  it "answers 404 for a stop that was removed from the run" do
    itin.destroy
    get :show, params: { id: itin.id }
    expect(response.status).to eq 404
    expect(JSON.parse(response.body)["data"]["code"]).to eq "itinerary_removed"

    put :update, params: { id: itin.id, itinerary: { status_code: 1 } }
    expect(response.status).to eq 404
  end

  it "gives an empty manifest when the driver has no open run" do
    get :index
    expect(response.status).to eq 200
    expect(JSON.parse(response.body)["data"]).to eq []
  end
end
