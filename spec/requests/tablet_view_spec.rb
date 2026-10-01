require "rails_helper"

# Office staff sign in on a tablet as "theirname/drivername" with their own
# password and see the driver's tablet without being able to change anything.
RSpec.describe "View-only tablet sign-in", type: :request do
  let(:driver) { create(:driver) }
  let(:office) { create(:user, username: "andrewv") }
  let!(:office_role) { create(:role, user: office, provider: driver.provider, level: Role::EDITOR_LEVEL) }
  let(:itin) { create(:itinerary, status_code: Itinerary::STATUS_PENDING) }

  def view_sign_in(password: "Password#1", as: office.username)
    post "/api/v1/driver_sign_in", params: { user: { username: " #{as.upcase}/#{driver.user.username} ", password: password } }, as: :json
    JSON.parse(response.body)
  end

  def headers_for(session)
    { "X-User-Username" => session["username"], "X-User-Token" => session["authentication_token"] }
  end

  it "signs in as the driver with a key of its own, marked view only" do
    driver.user.ensure_authentication_token
    driver.user.save!
    real = driver.user.reload.authentication_token
    s = view_sign_in["session"]
    expect(response.status).to eq 200
    expect(s).to include("username" => driver.user.username, "driver_id" => driver.id, "view_only" => true)
    expect(s["name"]).to end_with "(view only)"
    expect(s["authentication_token"]).to start_with(TabletView::PREFIX)
    expect(s["authentication_token"]).not_to eq real
  end

  it "reads what the driver reads, and refuses anything that changes data" do
    s = view_sign_in["session"]
    get "/api/v1/runs", headers: headers_for(s)
    expect(response.status).to eq 200
    put "/api/v1/itineraries/#{itin.id}/depart", headers: headers_for(s)
    expect(response.status).to eq 403
    expect(JSON.parse(response.body)["data"]["view_only"]).to include("andrewv")
    expect(itin.reload.status_code).to eq Itinerary::STATUS_PENDING
  end

  it "signs out without signing the driver out" do
    driver.user.ensure_authentication_token
    driver.user.save!
    real = driver.user.reload.authentication_token
    s = view_sign_in["session"]
    delete "/api/v2/sign_out", headers: headers_for(s)
    expect(response.status).to eq 200
    expect(driver.user.reload.authentication_token).to eq real
  end

  it "checks the office password, even with the open driver sign-in on" do
    FileUtils.touch(Api::V2::SessionsController::OPEN_SIGNIN_FLAG)
    view_sign_in(password: "nope")
    expect(response.status).to eq 401
  ensure
    FileUtils.rm_f(Api::V2::SessionsController::OPEN_SIGNIN_FLAG)
  end

  it "is for office staff only: a driver can't view another driver" do
    other = create(:driver, provider: driver.provider)
    view_sign_in(as: other.user.username)
    expect(response.status).to eq 401
  end

  it "is for the driver's own agency" do
    office_role.update!(provider: create(:provider))
    view_sign_in
    expect(response.status).to eq 401
  end

  it "never hands out the driver's real token from the other sign-in either" do
    post "/api/v2/sign_in", params: { user: { username: "andrewv/#{driver.user.username}", password: "Password#1" } }, as: :json
    token = JSON.parse(response.body)["data"]["session"]["authentication_token"]
    expect(token).to start_with(TabletView::PREFIX)
  end

  it "doesn't take a forged or other driver's key" do
    s = view_sign_in["session"]
    get "/api/v1/runs", headers: headers_for(s).merge("X-User-Token" => s["authentication_token"] + "x")
    expect(response.status).to eq 401
    other = create(:driver, provider: driver.provider)
    get "/api/v1/runs", headers: headers_for(s).merge("X-User-Username" => other.user.username)
    expect(response.status).to eq 401
  end
end
