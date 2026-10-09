require "rails_helper"

# 2026-10-09: the Save button on Runs/Trips for verification posted to a GET-only route.
RSpec.describe ReportsController do
  describe "verification saves" do
    before :each do
      @user = create(:role, level: 100).user
      @provider = @user.current_provider
      @request.env["devise.mapping"] = Devise.mappings[:user]
      sign_in @user
      @report = create(:custom_report, name: "show_runs_for_verification")
    end

    it "routes the form POSTs" do
      expect(post: "/en/reports/update_runs_for_verification/8").to route_to("reports#update_runs_for_verification", id: "8", locale: "en")
      expect(post: "/en/reports/update_trips_for_verification/8").to route_to("reports#update_trips_for_verification", id: "8", locale: "en")
    end

    it "saves the runs, keeps the run date, and returns to the page" do
      run = create(:run, provider: @provider, date: Date.current - 3)
      post :update_runs_for_verification, params: { id: @report.id, runs: { run.id.to_s => {
        start_odometer: "1000", end_odometer: "1050", actual_start_time: "8:00 AM", actual_end_time: "4:30 PM", paid: "false", name: "nope" } } }
      expect(response).to redirect_to("/en/reports/show_runs_for_verification/#{@report.id}")
      run.reload
      expect([run.start_odometer, run.end_odometer, run.paid]).to eq [1000, 1050, false]
      expect(run.actual_start_time.to_date).to eq run.date
      expect(run.name).not_to eq "nope"
    end

    it "leaves another agency runs alone" do
      other = create(:run, provider: create(:provider))
      post :update_runs_for_verification, params: { id: @report.id, runs: { other.id.to_s => { start_odometer: "5" } } }
      expect(other.reload.start_odometer).not_to eq 5
    end

    it "saves trip counts" do
      trip = create(:trip, provider: @provider)
      post :update_trips_for_verification, params: { id: @report.id, trips: { trip.id.to_s => { guest_count: "2", attendant_count: "1" } } }
      expect(response).to redirect_to("/en/reports/show_trips_for_verification/#{@report.id}")
      expect([trip.reload.guest_count, trip.attendant_count]).to eq [2, 1]
    end
  end
end
