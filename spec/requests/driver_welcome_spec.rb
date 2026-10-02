require "rails_helper"

# The driver tablet's sign-in screen (DriverWelcome): team totals, a line of
# the day and the weather, with no sign-in and nothing personal in it.
RSpec.describe "GET /api/v1/driver_welcome", type: :request do
  let(:complete) { TripResult.find_by(code: "COMP") || create(:trip_result, code: "COMP", name: "Complete") }
  before { allow(DriverWelcome).to receive(:weather).and_return({ place: "Victoria", temp: 84, kind: "storm", alerts: [{ event: "Flood Watch" }] }) }

  it "counts every agency's completed rides on the last service day and the past week, without signing in" do
    yesterday = Time.zone.yesterday
    create_list(:trip, 2, trip_result: complete, pickup_time: yesterday.in_time_zone.change(hour: 9))
    create(:trip, trip_result: complete, provider: create(:provider), pickup_time: yesterday.in_time_zone.change(hour: 10))
    create(:trip, trip_result: complete, pickup_time: (yesterday - 2).in_time_zone.change(hour: 9))
    create(:trip, pickup_time: yesterday.in_time_zone.change(hour: 11))           # not completed
    get "/api/v1/driver_welcome"
    expect(response).to be_successful
    body = JSON.parse(response.body)
    expect(body["rides"]).to eq("count" => 3, "day" => "yesterday", "week" => 4)
    expect(body["weather"]["alerts"].first["event"]).to eq "Flood Watch"
    expect(body["line"]).to be_present
    expect(response.body).not_to match(/customer|driver_id|first_name|last_name/)
  end

  it "says Friday on a Monday morning" do
    monday = Time.zone.today.prev_occurring(:monday)   # a past one: a future trip can't be Complete
    friday = monday - 3
    create(:trip, trip_result: complete, pickup_time: friday.in_time_zone.change(hour: 9))
    expect(DriverWelcome.last_service_day(monday)).to eq [friday, 1]
    expect(DriverWelcome.day_label(friday, monday)).to eq "on Friday"
  end

  it "keeps only the first part of a two-part forecast" do
    expect(DriverWelcome.short_text("Chance Showers And Thunderstorms then Showers And Thunderstorms")).to eq "Chance Showers And Thunderstorms"
    expect(DriverWelcome.short_text("Mostly Sunny")).to eq "Mostly Sunny"
  end

  it "names the forecast's icon" do
    expect(DriverWelcome.kind("Showers And Thunderstorms", true)).to eq "storm"
    expect(DriverWelcome.kind("Mostly Sunny", true)).to eq "partly"
    expect(DriverWelcome.kind("Clear", false)).to eq "clear-night"
    expect(DriverWelcome.kind("Patchy Fog", true)).to eq "fog"
  end
end
