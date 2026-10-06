require "rails_helper"

# Goliad, 2026-10-06: Reports > Vehicle Summary.
RSpec.describe ReportsController do
  describe "vehicle_summary" do
    render_views

    before :each do
      @user = create(:role, level: 100).user
      @provider = @user.current_provider
      @request.env["devise.mapping"] = Devise.mappings[:user]
      sign_in @user
      @report = create(:custom_report, name: 'vehicle_summary', version: '2', redirect_to_results: true)
      allow_any_instance_of(VehicleSummaryReport).to receive(:road_miles).and_return(3.0)
      garage = create(:garage_address, provider: @provider)
      @bus = create(:vehicle, provider: @provider, name: "Bus 7", garage_address: garage)
      day = Date.current
      @run = create(:run, provider: @provider, vehicle: @bus, date: day, name: "Run A")
      @run.update_columns(start_odometer: 500, end_odometer: 540, actual_start_time: Time.zone.local(day.year, day.month, day.day, 7),
                          actual_end_time: Time.zone.local(day.year, day.month, day.day, 11))
      trip = create(:trip, provider: @provider, run: @run, trip_result: TripResult.find_by(code: "COMP") || create(:trip_result, code: "COMP"))
      Itinerary.create!(run: @run, trip: trip, leg_flag: 1, address: trip.pickup_address,
                        arrival_time: Time.zone.local(day.year, day.month, day.day, 8), finish_time: Time.zone.local(day.year, day.month, day.day, 8, 5))
      Itinerary.create!(run: @run, trip: trip, leg_flag: 2, address: trip.dropoff_address,
                        finish_time: Time.zone.local(day.year, day.month, day.day, 10))
      @open = create(:run, provider: @provider, vehicle: @bus, date: day, name: "Run B")
      create(:trip, provider: @provider, run: @open)
    end

    let(:params) { { id: @report.id, query: { start_date: Date.current.to_s, before_end_date: Date.current.to_s } } }

    it "shows revenue and non-revenue hours and miles by bus, and the runs not counted" do
      get :vehicle_summary, params: params
      expect(response).to be_successful
      v = assigns(:summary).by_vehicle.first
      expect(v).to include(vehicle: "Bus 7", runs: 1, total_hours: 4.0, revenue_hours: 2.0, total_miles: 40.0, non_revenue_miles: 6.0, revenue_miles: 34.0)
      expect(response.body).to include("Revenue hours", "Runs not counted (1 of 2)", "Run B", "odometer readings")
    end

    it "downloads the summary and a row per run as Excel, numbers as numbers" do
      get :vehicle_summary, params: params.deep_merge(query: { report_format: "xlsx" })
      expect(response).to be_successful
      rows = RubyXL::Parser.parse_buffer(response.body)[0].sheet_data.rows.compact.map { |r| r.cells.map { |c| c&.value } }
      bus = rows.find { |r| r.first == "Bus 7" }
      expect(bus[2..7]).to eq [4, 2, 2, 40, 34, 6]
      expect(rows.find { |r| r[1] == "Run B" }[4]).to eq "No"
    end
  end
end
