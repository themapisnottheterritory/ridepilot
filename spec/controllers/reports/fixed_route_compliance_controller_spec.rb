require "rails_helper"

RSpec.describe ReportsController do
  describe "fixed_route_compliance" do
    render_views

    before :each do
      @user = create(:role, level: 100).user
      @provider = @user.current_provider
      @request.env["devise.mapping"] = Devise.mappings[:user]
      sign_in @user
      @report = create(:custom_report, name: 'fixed_route_compliance', version: '2', redirect_to_results: true)
      @run, @driver, @route = build_fixed_run(@provider)
      @run.update_columns(actual_start_time: Time.current - 3.hours, actual_end_time: Time.current, start_odometer: 100, end_odometer: 130)
      FixedRouteStopVisit.create!(provider: @provider, run: @run, fixed_route: @route, external_route_id: "r1", external_stop_id: "s1", trip_id: "run_01", stop_name: "Depot", sequence: 0, status: "served", dwell_seconds: 25, deviation_seconds: 5, client_uuid: "v1")
      FixedRouteStopVisit.create!(provider: @provider, run: @run, fixed_route: @route, external_route_id: "r1", external_stop_id: "s2", trip_id: "run_01", stop_name: "Mall", sequence: 1, status: "skipped", deviation_seconds: -120, scheduled_time: "08:10", client_uuid: "v2")
      VehicleInspectionReport.create!(run: @run, provider: @provider, vehicle: @run.vehicle, driver: @driver, phase: "pre", odometer: 100, safe_to_operate: true, submitted_at: Time.current - 3.hours)
    end

    it "renders one row per run with the skipped stop named" do
      get :fixed_route_compliance, params: { id: @report.id, query: { start_date: Date.current.to_s, before_end_date: Date.current.to_s } }
      expect(response).to be_successful
      expect(assigns(:grand)[:runs]).to eq 1
      expect(assigns(:grand)[:skipped]).to eq 1
      expect(assigns(:grand)[:no_post]).to eq 1
      expect(response.body).to include("Route: Red")
      expect(response.body).to include("no post-trip, 1 skipped, 1 early")
      expect(response.body).to include("Skipped stops:")
      expect(response.body).to include("Mall (run_01, published 08:10")
    end

    it "filters by driver and bus" do
      get :fixed_route_compliance, params: { id: @report.id, query: { start_date: Date.current.to_s, before_end_date: Date.current.to_s, driver_id: @driver.id, vehicle_id: @run.vehicle_id } }
      expect(assigns(:grand)[:runs]).to eq 1
      get :fixed_route_compliance, params: { id: @report.id, query: { start_date: Date.current.to_s, before_end_date: Date.current.to_s, driver_id: @driver.id + 999 } }
      expect(assigns(:grand)[:runs]).to eq 0
      expect(response.body).to include("No fixed-route runs in this range")
    end

    it "exports csv with the detail section" do
      get :fixed_route_compliance, params: { id: @report.id, query: { start_date: Date.current.to_s, before_end_date: Date.current.to_s, report_format: "csv" } }
      expect(response).to be_successful
      expect(response.body).to include("Skipped stops and early departures")
      expect(response.body).to include("skipped,run_01,Mall,08:10")
    end
  end
end
