require "rails_helper"

# Which build each driver tablet runs (1.0.20+ reports it).
RSpec.describe "Tablet app version reporting", type: :request do
  let(:driver) { create(:driver) }
  before { TabletAppVersion.redis.del(TabletAppVersion::KEY) }
  after  { TabletAppVersion.redis.del(TabletAppVersion::KEY) }

  it "is recorded at sign-in" do
    post "/api/v1/driver_sign_in", params: { user: { username: driver.user.username, password: "Password#1" },
                                            app: { version: "1.0.20", version_code: 21, build_time: "2026-10-01 12:24 CT" } }, as: :json
    expect(response.status).to eq 200
    expect(TabletAppVersion.find(driver.user.username)).to include("version" => "1.0.20", "code" => "21", "build" => "2026-10-01 12:24 CT")
  end

  it "is recorded from the headers on any request, so a tablet that stays signed in still reports an update" do
    s = driver.user.tap(&:ensure_authentication_token).tap(&:save!)
    get "/api/v1/runs", headers: { "X-User-Username" => s.username, "X-User-Token" => s.authentication_token,
                                   "X-App-Version" => "1.0.20", "X-App-Code" => "21", "X-App-Build" => "2026-10-01 12:24 CT" }
    expect(response.status).to eq 200
    expect(TabletAppVersion.find(s.username)["version"]).to eq "1.0.20"
  end

  it "ignores a request that doesn't say, and never records a view-only tablet as the driver's" do
    office = create(:user, username: "andrewv")
    create(:role, user: office, provider: driver.provider, level: Role::EDITOR_LEVEL)
    post "/api/v1/driver_sign_in", params: { user: { username: "andrewv/#{driver.user.username}", password: "Password#1" },
                                            app: { version: "1.0.20" } }, as: :json
    key = JSON.parse(response.body)["session"]["authentication_token"]
    get "/api/v1/runs", headers: { "X-User-Username" => driver.user.username, "X-User-Token" => key, "X-App-Version" => "1.0.20" }
    expect(response.status).to eq 200
    expect(TabletAppVersion.find(driver.user.username)).to be_nil
  end
end
