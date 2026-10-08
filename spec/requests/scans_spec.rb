require "rails_helper"

# 2026-10-08: the tablet's Scan odometer / Scan pump buttons.
RSpec.describe "Odometer and pump scans", type: :request do
  let(:run)    { create(:run, date: Date.current).tap { |r| r.driver.update_column(:provider_id, r.provider_id) } }
  let(:driver) { run.driver }
  let(:headers) do
    driver.user.ensure_authentication_token; driver.user.save!
    { "X-User-Username" => driver.user.username, "X-User-Token" => driver.user.authentication_token, "X-App-Code" => "35" }
  end
  let(:photo) { Rack::Test::UploadedFile.new(StringIO.new("\xFF\xD8fakejpeg".b), "image/jpeg", true, original_filename: "odo.jpg") }

  def scan(kind, model_says)
    allow_any_instance_of(ScanReader).to receive(:post_model).and_return(model_says)
    post "/api/v1/scans", params: { kind: kind, run_id: run.id, photo: photo }, headers: headers
    expect(response.status).to eq 200
    JSON.parse(response.body)
  end

  it "reads an odometer, keeps the photo, and checks it against the bus's last reading" do
    Run.where(id: run.id).update_all(start_odometer: nil)
    create(:run, vehicle: run.vehicle, date: Date.yesterday, start_odometer: 48_000, end_odometer: 48_100)
    data = scan("odometer", 'Sure: {"miles": "48,211"}')
    expect(data).to include("miles" => 48_211, "last_known_odometer" => 48_100, "read" => true, "warning" => nil)
    s = ReadingScan.find(data["scan_id"])
    expect(s.value).to eq 48_211
    expect(s.photo).to be_attached
  end

  it "warns when the reading is below the last one" do
    create(:run, vehicle: run.vehicle, date: Date.yesterday, start_odometer: 50_000, end_odometer: 50_100)
    expect(scan("odometer", '{"miles": 48211}')["warning"]).to include("lower than")
  end

  it "reads a pump" do
    data = scan("pump", '{"gallons": 21.437, "price_per_gallon": "$2.879", "total": 61.72}')
    expect(data).to include("gallons" => 21.437, "price_per_gallon" => 2.879, "total" => 61.72)
  end

  it "fails open when the model gives nothing" do
    data = scan("odometer", "")
    expect(data["read"]).to eq false
    expect(data["miles"]).to be_nil
    expect(ReadingScan.find(data["scan_id"]).error).to be_present
  end

  it "ties the scan to the submitted report with the number the driver kept" do
    id = scan("odometer", '{"miles": 48211}')["scan_id"]
    item = create(:vehicle_inspection, provider: run.provider)
    post "/api/v1/inspection_reports",
         params: { inspection_report: { run_id: run.id, phase: "pre", odometer: 48_217, safe_to_operate: true },
                   items: [{ vehicle_inspection_id: item.id, status: "ok" }], scan_ids: [id] }.to_json,
         headers: headers.merge("Content-Type" => "application/json")
    expect(response.status).to eq 200
    s = ReadingScan.find(id)
    expect(s.vehicle_inspection_report_id).to be_present
    expect(s.accepted_value).to eq 48_217
    expect(s).to be_corrected
  end
end
