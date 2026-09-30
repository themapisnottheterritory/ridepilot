require "rails_helper"

# The tablet sign-in both driver apps use. The Demand Response app reads
# data.session; the fixed-route app reads session at the top level.
RSpec.describe "POST /api/v1/driver_sign_in", type: :request do
  let(:driver) { create(:driver) }

  it "returns the session in both places a tablet looks" do
    post "/api/v1/driver_sign_in", params: { user: { username: driver.user.username, password: "Password#1" } }, as: :json
    expect(response.status).to eq 200
    body = JSON.parse(response.body)
    expect(body["data"]["session"]).to include("driver_id" => driver.id, "username" => driver.user.username)
    expect(body["session"]).to eq body["data"]["session"]
    expect(body["session"]["authentication_token"]).to be_present
  end

  it "still says no, with a 401 and no session, for a wrong password" do
    post "/api/v1/driver_sign_in", params: { user: { username: driver.user.username, password: "nope" } }, as: :json
    expect(response.status).to eq 401
    expect(JSON.parse(response.body)).not_to have_key("session")
  end
end
