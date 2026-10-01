require "rails_helper"

# The tracking map refreshes a run every few seconds. A published stop whose
# itinerary row no longer exists made
# every refresh a 500 (run 347, 2026-10-01).
RSpec.describe Cad::CadController, type: :controller do
  login_admin_as_current_user

  let(:run)  { create(:run, provider: @current_user.current_provider, start_odometer: 100, date: Date.today) }
  let!(:kept) { create(:itinerary, run: run) }
  let!(:gone) { create(:itinerary, run: run) }

  before do
    [kept, gone].each_with_index { |i, n| PublicItinerary.create!(run: run, itinerary: i, sequence: n, eta: i.eta) }
    Itinerary.unscoped.where(id: gone.id).delete_all   # gone outright, not soft-deleted
  end

  it "draws the upcoming path past a stop deleted since the last publish" do
    expect(PublicItinerary.where(run_id: run.id).map(&:itinerary)).to include(nil)
    get :reload_run, params: { cad: { run_id: run.id }, options: { upcoming_path: "true", prior_path: "false", stops: "false" } }, format: :js, xhr: true
    expect(response.status).to eq 200
  end

  it "shows no popup for a deleted stop" do
    get :stop_info, params: { itinerary_id: gone.id }, format: :js, xhr: true
    expect(response.status).to eq 200
  end
end
