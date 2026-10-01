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

  it "ignores spaces and capitals around the username, as the web sign-in does" do
    post "/api/v1/driver_sign_in", params: { user: { username: "  #{driver.user.username.upcase} ", password: "Password#1" } }, as: :json
    expect(response.status).to eq 200
    expect(JSON.parse(response.body)["session"]["username"]).to eq driver.user.username
  end

  context "initials typed in lowercase" do
    before { driver.user.update!(password: "JT123456", password_confirmation: "JT123456") }

    it "lets a driver in with jt123456, Jt123456 or jT123456 for JT123456" do
      %w[jt123456 Jt123456 jT123456].each do |pw|
        post "/api/v1/driver_sign_in", params: { user: { username: driver.user.username, password: pw } }, as: :json
        expect(response.status).to eq(200), "#{pw} should sign in"
      end
    end

    it "still refuses other wrong passwords, and other kinds of case slip" do
      %w[jt123457 Jt12345 JT12345 xx123456].each do |pw|
        post "/api/v1/driver_sign_in", params: { user: { username: driver.user.username, password: pw } }, as: :json
        expect(response.status).to eq(401), "#{pw} should be refused"
      end
    end
  end

  it "still says no, with a 401 and no session, for a wrong password" do
    post "/api/v1/driver_sign_in", params: { user: { username: driver.user.username, password: "nope" } }, as: :json
    expect(response.status).to eq 401
    expect(JSON.parse(response.body)).not_to have_key("session")
  end
end
