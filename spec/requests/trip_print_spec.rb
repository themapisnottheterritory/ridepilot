require "rails_helper"

# Trips > Print (2026-10-08, Michelle): the filtered trips on a sheet to write on.
RSpec.describe "Trips print sheet", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:staff) { create(:role, level: Role::ADMIN_LEVEL).user }
  let(:provider) { staff.current_provider }
  let(:day) { Date.current + 1 }
  let(:run) { create(:run, provider: provider, date: day, name: "UDR 3") }
  let!(:on_run) { create(:trip, provider: provider, run: run, pickup_time: day.in_time_zone.change(hour: 9), appointment_time: day.in_time_zone.change(hour: 9, min: 30)) }
  let!(:loose) { create(:trip, provider: provider, run: nil, pickup_time: day.in_time_zone.change(hour: 13)) }

  before do
    sign_in staff
    get "/en/trips", params: { trip_filters: { start: day.strftime("%a %b %d, %Y"), end: day.strftime("%a %b %d, %Y") } }
  end

  it "is the Print button on the Trips page" do
    expect(response.body).to include("Print").and include("/en/trips/report")
  end

  it "groups by run, with the riders, times, notes space and no auto-print" do
    get "/en/trips/report"
    expect(response).to be_successful
    body = response.body
    expect(body).to include("UDR 3").and include("Not on a run")
    expect(body).to include(ERB::Util.h(on_run.customer.name)).and include(ERB::Util.h(loose.customer.name))
    expect(body).to match(/appt +9:30am/)
    expect(body).to include("c-notes")
    expect(body).not_to include("print();")
    expect(body.index("UDR 3")).to be < body.index("Not on a run")
  end

  it "only names the filters that narrow the list" do
    get "/en/trips/report"
    expect(response.body).to include("all trips for these dates")
    cancel = TripResult.find_by(code: "CANC") || TripResult.create!(code: "CANC", name: "Cancelled")
    get "/en/trips", params: { trip_filters: { start: day.strftime("%a %b %d, %Y"), end: day.strftime("%a %b %d, %Y"), trip_result_id: [cancel.id.to_s] } }
    get "/en/trips/report"
    expect(response.body).to include("Result: Cancelled")
  end

  it "groups by day" do
    get "/en/trips/report", params: { group: "day" }
    expect(response.body).to include(day.strftime("%A, %B %-d"))
    expect(response.body).to include("<th class=\"c-run\">Run</th>")
  end

  it "downloads as a PDF" do
    get "/en/trips/report.pdf", params: { group: "run" }
    expect(response).to be_successful
    expect(response.media_type).to eq "application/pdf"
    expect(response.body[0, 4]).to eq "%PDF"
  end
end
