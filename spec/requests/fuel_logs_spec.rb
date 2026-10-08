require "rails_helper"

# 2026-10-08: "Log fuel" on the tablet for fueling mid-shift, plus the
# post-trip's gallons, both in fuel_logs.
RSpec.describe "Fuel logs", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:run)    { create(:run, date: Date.current).tap { |r| r.driver.update_column(:provider_id, r.provider_id) } }
  let(:driver) { run.driver }
  let(:headers) do
    driver.user.ensure_authentication_token; driver.user.save!
    { "X-User-Username" => driver.user.username, "X-User-Token" => driver.user.authentication_token,
      "X-App-Code" => "35", "Content-Type" => "application/json" }
  end
  let(:pump_scan) do
    ReadingScan.create!(kind: "pump", run: run, driver: driver, value: 21.44,
                        reading: { "gallons" => 21.437, "price_per_gallon" => 2.879, "total" => 61.72 })
  end

  def log_fuel(gallons:, uuid: "abc-1", scans: [], odometer: 48_300)
    post "/api/v1/fuel_logs", headers: headers, params: {
      fuel_log: { run_id: run.id, gallons: gallons, odometer: odometer, client_uuid: uuid, fueled_at: Time.current.iso8601 },
      scan_ids: scans.map(&:id) }.to_json
    response
  end

  it "logs a mid-shift fill with the price and total from the pump photo" do
    expect(log_fuel(gallons: 21.437, scans: [pump_scan]).status).to eq 200
    log = FuelLog.last
    expect(log).to have_attributes(source: "mid_shift", vehicle_id: run.vehicle_id, odometer: 48_300)
    expect(log.gallons.to_f).to eq 21.437
    expect(log.price_per_gallon.to_f).to eq 2.879
    expect(log.total_cost.to_f).to eq 61.72
    expect(pump_scan.reload.fuel_log_id).to eq log.id
  end

  it "leaves the money blank when the driver changed the gallons" do
    log_fuel(gallons: 18.2, scans: [pump_scan])
    expect(FuelLog.last.total_cost).to be_nil
    expect(pump_scan.reload).to be_corrected
  end

  it "a resend of the same entry isn't a second fill" do
    2.times { expect(log_fuel(gallons: 10).status).to eq 200 }
    expect(FuelLog.count).to eq 1
  end

  it "refuses an impossible amount" do
    expect(log_fuel(gallons: 1500).status).to eq 422
    expect(log_fuel(gallons: 0, uuid: "z").status).to eq 422
  end

  it "doesn't count as the post-trip" do
    log_fuel(gallons: 10)
    expect(VehicleInspectionReport.where(run_id: run.id).count).to eq 0
  end

  it "puts the post-trip's gallons in fuel_logs too" do
    item = create(:vehicle_inspection, provider: run.provider)
    post "/api/v1/inspection_reports", headers: headers, params: {
      inspection_report: { run_id: run.id, phase: "post", odometer: 48_400, gallons: 21.437, safe_to_operate: true },
      items: [{ vehicle_inspection_id: item.id, status: "ok" }], scan_ids: [pump_scan.id] }.to_json
    expect(response.status).to eq 200
    log = FuelLog.find_by(source: "post_trip")
    expect(log.gallons.to_f).to eq 21.44   # the report keeps 2 decimals
    expect(log.total_cost.to_f).to eq 61.72
    expect(log.vehicle_inspection_report_id).to be_present
  end

  it "shows on the bus page" do
    log_fuel(gallons: 21.437, scans: [pump_scan])
    staff = create(:role, level: Role::ADMIN_LEVEL).user
    run.vehicle.update_column(:provider_id, staff.current_provider_id)
    sign_in staff
    get "/en/vehicles/#{run.vehicle_id}"
    expect(response).to be_successful
    expect(response.body).to include("Mid-shift").and include("21.437").and include("$61.72")
  end
end
