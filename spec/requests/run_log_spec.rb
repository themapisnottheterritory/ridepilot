require "rails_helper"

# 2026-10-08: Shelby's "Vehicle Summary Report" layout, one row per run.
RSpec.describe "Vehicle Summary by Run", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:staff) { create(:role, level: Role::ADMIN_LEVEL).user }
  let(:provider) { staff.current_provider }
  let(:day) { Date.current - 2 }
  let(:report) { CustomReport.find_or_create_by!(name: "run_log") { |c| c.title = "Vehicle Summary by Run"; c.version = "2"; c.redirect_to_results = true } }
  let(:at) { ->(h, m = 0) { day.in_time_zone.change(hour: h, min: m) } }
  # GPS: 2 miles to the first pick-up, 30 between pick-ups, 3 back
  let(:gps) do
    Class.new do
      def initialize(at) = @at = at
      def miles(unit, from, to) = { [8, 0] => 2.0, [8, 15] => 30.0, [12, 0] => 3.0 }[[from.hour, from.min]]
      def fixes(*) = []
    end.new(at)
  end
  let(:udr) do
    create(:run, provider: provider, date: day, name: "UDR 3", start_odometer: 50_000, end_odometer: 50_035,
                 actual_start_time: at.(8), actual_end_time: at.(12, 30))
  end

  before do
    RunLogReport::MEMORY.clear
    comp = TripResult.find_by(code: "COMP") || TripResult.create!(code: "COMP", name: "Complete")
    trip = create(:trip, provider: provider, run: udr, pickup_time: at.(8, 15), trip_result: comp, guest_count: 1, drive_distance: 12.5)
    create(:itinerary, run: udr, trip: trip, leg_flag: 1, arrival_time: at.(8, 15), finish_time: at.(8, 17))
    create(:itinerary, run: udr, trip: trip, leg_flag: 2, arrival_time: at.(11, 58), finish_time: at.(12, 0))
    create(:run, provider: provider, date: day, name: "RVIC1")   # nothing recorded, no trips: left out
    sign_in staff
  end

  def build
    RunLogReport.new(provider_ids: [provider.id], start_date: day, end_date: day + 1, gps: gps, compare: ->(_) { nil }).run!
  end

  it "works out Shelby's columns from the tablet, odometers and GPS" do
    row = build.rows.find { |r| r.route == "UDR 3" }
    expect(row.mode).to eq "UDR"
    expect([row.start_odo, row.first_pickup_odo, row.last_dropoff_odo, row.end_odo]).to eq [50_000, 50_002.0, 50_032.0, 50_035]
    expect(row.revenue_miles).to eq 30.0
    expect(row.deadhead_miles).to eq 5.0
    expect(row.revenue_hours).to eq 3.75      # 8:15 to 12:00
    expect(row.deadhead_hours).to eq 0.75     # 8:00-8:15 and 12:00-12:30
    expect(row.upt).to eq 2                   # rider + guest
    expect(row.pmt).to eq 25.0                # 12.5 road miles x 2 riders
    expect(row.notes).to include("Pick-up and drop-off odometers from GPS")
    expect(row).to be_complete
  end

  it "takes the earlier of the tablet start and the first pick-up" do
    udr.update_columns(actual_start_time: at.(8, 30))
    row = build.rows.find { |r| r.route == "UDR 3" }
    expect(row.start_at).to eq at.(8, 15)
    expect(row.notes).to include("Started on the tablet after the first pick-up")
  end

  it "says what's missing when the run wasn't closed out" do
    udr.update_columns(actual_end_time: nil, end_odometer: nil)
    row = build.rows.find { |r| r.route == "UDR 3" }
    expect(row.notes).to include("Not closed out on the tablet")
    expect(row.last_dropoff_odo).to eq 50_032.0   # start + GPS to the first pick-up + GPS between
    expect(row).not_to be_complete
  end

  it "builds a commuter row from the GPS trips and the AM run's driver" do
    route = FixedRoute.create!(provider: provider, name: "Vic1+Edna", kind: "commuter")
    am = create(:run, provider: provider, date: day, name: "Victoria 1 AM", service_mode: "fixed_route", fixed_route: route)
    pm = create(:run, provider: provider, date: day, name: "Victoria 1 PM", service_mode: "fixed_route", fixed_route: route)
    blank = create(:run, provider: provider, date: day, name: "Edna PM", service_mode: "fixed_route",
                         fixed_route: FixedRoute.create!(provider: provider, name: "Edna", kind: "commuter"), driver: nil, vehicle: nil)
    trip = ->(dep, arr) { { "date" => day.to_s, "bus" => "1797", "dep" => dep, "stops" => [{ "arr" => dep }, { "arr" => arr }] } }
    compare = lambda do |file|
      { "index.json" => [{ "route_id" => "vic1-edna-inteplast", "name" => "Vic1 + Edna — Inteplast", "short_name" => "Vic1+Edna", "trips" => 2 }],
        "vic1-edna-inteplast.json" => { "trips" => [trip.(5 * 3600 + 45 * 60, 7 * 3600), trip.(7 * 3600 + 20 * 60, 8 * 3600)] } }[file]
    end
    rows = RunLogReport.new(provider_ids: [provider.id], start_date: day, end_date: day + 1, gps: gps, compare: compare).run!
    gps_row = rows.rows.find { |r| r.mode == "Commuter" && r.bus == "1797" }
    expect(gps_row.run_id).to eq am.id                 # morning trips -> the AM run and its driver
    expect(gps_row.first_pickup_at).to eq at.(5, 45)
    expect(gps_row.last_dropoff_at).to eq at.(8)
    no_gps = rows.rows.find { |r| r.mode == "Commuter" && r.run_id == pm.id }
    expect(no_gps.notes.join).to include("No GPS")     # the PM run happened (it has a driver) but no GPS
    expect(rows.commuter_without_data).to eq 1         # the Edna PM run, nothing recorded
  end

  it "keeps a finished day and rebuilds it when a run changes" do
    first = build.rows.find { |r| r.route == "UDR 3" }.start_odo
    udr.update!(start_odometer: 49_990)
    expect(build.rows.find { |r| r.route == "UDR 3" }.start_odo).to eq 49_990
    expect(first).to eq 50_000
  end

  it "is a report page with Shelby's columns, and a CSV" do
    allow(GpsMiles).to receive(:new).and_return(gps)
    allow(FixedRouteRows).to receive(:fetcher).and_return(->(_) { nil })
    q = { query: { "start_date(1i)" => day.year, "start_date(2i)" => day.month, "start_date(3i)" => day.day,
                   "before_end_date(1i)" => day.year, "before_end_date(2i)" => day.month, "before_end_date(3i)" => day.day } }
    get "/en/reports/run_log/#{report.id}", params: q
    expect(response).to be_successful
    body = response.body
    expect(body).to include("First Pickup Odometer").and include("Total Deadhead Miles").and include("UDR 3")
    get "/en/reports/run_log/#{report.id}", params: q.deep_merge(query: { report_format: "csv" })
    expect(response.body).to include("Mode,Date,Driver,Route,Bus #").and include("UDR,")
  end
end
