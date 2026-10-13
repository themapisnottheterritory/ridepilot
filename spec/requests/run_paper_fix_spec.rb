require "rails_helper"

# Fix from paper (2026-10-13): Hville1 on Mon 10/5 ran on paper; every trip was set
# Completed on the web, no stop had a time, and the reports couldn't count it.
RSpec.describe "Fix from paper", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:day) { Date.yesterday }
  let(:at) { ->(h, m = 0) { day.in_time_zone.change(hour: h, min: m) } }
  let(:run) do
    r = create(:run, name: "Hville1", date: day, scheduled_start_time: at.(7), scheduled_end_time: at.(16))
    r.driver.update_column(:provider_id, r.provider_id)
    r.vehicle.update_column(:provider_id, r.provider_id)
    r
  end
  let(:provider) { run.provider }
  let(:trip) do
    t = build(:trip, provider: provider, run: run, pickup_time: at.(9, 30), appointment_time: nil)
    t.save(validate: false)
    t
  end
  let!(:up) { create(:itinerary, run: run, trip: trip, leg_flag: 1, status_code: 0, time: at.(9, 30)) }
  let!(:down) { create(:itinerary, run: run, trip: trip, leg_flag: 2, status_code: 0, time: at.(10)) }
  let(:admin) { create(:super_admin) }
  before do
    sign_in admin
    { "COMP" => "Complete", "NS" => "No-show", "MT" => "Missed Trip" }.each { |c, n| TripResult.find_or_create_by!(code: c) { |r| r.name = n } }
  end

  def post_paper(run_fields: {}, stops: {}, results: {})
    post "/en/runs/#{run.id}/paper", params: { paper: { run: run_fields, stops: stops, results: results } }
  end

  it "shows the run's stops to fill in" do
    get "/en/runs/#{run.id}/paper"
    expect(response.status).to eq 200
    expect(response.body).to include("Fix from paper: Hville1", "Pick up", "Drop off", trip.customer.name)
    get "/en/runs/#{run.id}"
    expect(response.body).to include("Fix from paper")
  end

  it "saves the run's actuals and the stop times, marked as typed, and the result" do
    post_paper(run_fields: { start: "08:55", end: "16:00", start_odometer: "40494", end_odometer: "40650" },
               stops: { up.id => { arrived: "09:28", done: "09:31" }, down.id => { done: "09:58" } },
               results: { trip.id => "COMP" })
    expect(response).to redirect_to("/en/runs/#{run.id}")
    follow_redirect!
    expect(response.body).to include("2 stop times typed")
    run.reload; up.reload; down.reload
    expect([run.actual_start_time, run.actual_end_time, run.start_odometer, run.end_odometer]).to eq [at.(8, 55), at.(16), 40494, 40650]
    expect([up.arrival_time, up.finish_time, up.status_code, up.times_typed_by]).to eq [at.(9, 28), at.(9, 31), Itinerary::STATUS_COMPLETED, admin.username]
    expect([down.arrival_time, down.finish_time]).to eq [at.(9, 58), at.(9, 58)]   # one time: arrived and done then
    expect(trip.reload.trip_result.code).to eq "COMP"
  end

  it "leaves a tapped stop alone when its time isn't changed" do
    up.update_columns(arrival_time: at.(9, 29), finish_time: at.(9, 30), status_code: Itinerary::STATUS_COMPLETED)
    post_paper(stops: { up.id => { arrived: "09:29", done: "09:30" }, down.id => { done: "10:02" } })
    expect(up.reload.times_typed_by).to be_nil
    expect(down.reload.times_typed_by).to eq admin.username
  end

  it "saves nothing when anything is wrong, and says what" do
    post_paper(run_fields: { start_odometer: "40650", end_odometer: "40494" },
               stops: { up.id => { arrived: "09:40", done: "09:31" }, down.id => { done: "09:10" } })
    expect(response.status).to eq 422
    expect(response.body).to include("Nothing was saved", "End odometer 40494 is less than the start 40650", "before arriving at 9:40 AM")
    expect(up.reload.finish_time).to be_nil
    expect(run.reload.start_odometer).to be_nil
  end

  it "refuses a drop-off before its pick-up" do
    post_paper(stops: { up.id => { done: "09:31" }, down.id => { done: "09:20" } })
    expect(response.body).to include("dropped off at 9:20 AM, before the pick-up at 9:31 AM")
  end

  it "holds a typed no-show to the pick-up window" do
    post_paper(stops: { up.id => { arrived: "10:15", done: "10:20" } }, results: { trip.id => "NS" })
    expect(response.status).to eq 422
    expect(response.body).to include("Missed Trip")
    post_paper(stops: { up.id => { arrived: "09:28", done: "09:36" } }, results: { trip.id => "NS" })
    expect(trip.reload.trip_result.code).to eq "NS"
    expect(up.reload.status_code).to eq Itinerary::STATUS_OTHER
  end
end
