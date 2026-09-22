require "rails_helper"

RSpec.describe FixedRouteCompliance do
  let(:provider) { create(:provider) }
  let!(:setup)   { build_fixed_run(provider) }
  let(:run)      { setup[0] }
  let(:driver)   { setup[1] }
  let(:route)    { setup[2] }

  def visit(run, stop, status, attrs = {})
    FixedRouteStopVisit.create!({ provider: provider, run: run, fixed_route: route, external_route_id: "r1", external_stop_id: stop,
      trip_id: "run_01", stop_name: stop, sequence: 1, status: status, client_uuid: SecureRandom.uuid }.merge(attrs))
  end

  it "scores a run on stops, early departures, riders and the two inspections" do
    run.update_columns(actual_start_time: Time.current - 3.hours, actual_end_time: Time.current, start_odometer: 1000, end_odometer: 1042)
    visit(run, "s1", "served", dwell_seconds: 20, deviation_seconds: 10)
    visit(run, "s2", "served", dwell_seconds: 40, deviation_seconds: -95, departed_at: Time.current - 2.hours, scheduled_time: "08:10")
    visit(run, "s3", "skipped", deviation_seconds: 400)
    FixedRouteBoarding.create!(provider: provider, run: run, rider_category: RiderCategory.first, boarded_count: 2, recorded_at: Time.current, client_uuid: "b1")
    VehicleInspectionReport.create!(run: run, provider: provider, vehicle: run.vehicle, driver: driver, phase: "pre", odometer: 1000, safe_to_operate: true, submitted_at: Time.current - 3.hours)

    rows = described_class.new(provider.id, start_date: Date.today - 1, end_date: Date.today + 1).rows
    expect(rows.size).to eq 1
    r = rows.first
    expect(r.stops_served).to eq 2
    expect(r.stops_skipped).to eq 1
    expect(r.early).to eq 1
    expect(r.late).to eq 1
    expect(r.avg_dwell).to eq 30
    expect(r.boarded).to eq 2
    expect(r.miles).to eq 42
    expect(r.pre_trip).to be_present
    expect(r.post_trip).to be_nil
    expect(r.issues).to eq ["no post-trip", "1 skipped", "1 early"]
    expect(r.skipped_list.first[:stop]).to eq "s3"
    expect(r.early_list.first[:minutes]).to eq 1.6

    t = described_class.new(provider.id, start_date: Date.today - 1, end_date: Date.today + 1).totals(rows)
    expect(t[:skip_rate]).to eq 33.3
    expect(t[:no_post]).to eq 1
    expect(t[:clean]).to eq 0
  end

  it "filters by route, driver and vehicle, and flags a run with no stop data" do
    run.update_columns(actual_start_time: Time.current - 1.hour)
    svc = described_class.new(provider.id, start_date: Date.today - 1, end_date: Date.today + 1, driver_id: driver.id, vehicle_id: run.vehicle_id, fixed_route_id: route.id)
    expect(svc.rows.map(&:run)).to eq [run]
    expect(svc.rows.first.issues).to include("no stop data", "no pre-trip")
    expect(described_class.new(provider.id, start_date: Date.today - 1, end_date: Date.today + 1, driver_id: driver.id + 999).rows).to be_empty
  end
end
