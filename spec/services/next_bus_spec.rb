require "rails_helper"

# Next Bus on a tiny made-up timetable: one route, a bus that runs north
# (Base -> Main @ Oak -> North End) and back from North End, weekdays only,
# with a holiday.
RSpec.describe NextBus do
  FEED = {
    "stops.txt" => <<~CSV,
      stop_id,stop_code,stop_name,stop_lat,stop_lon
      A,1,Rio Grande @ Base,28.8000,-97.0000
      B,2,N Main @ E Oak (Northbound),28.8100,-97.0000
      C,3,North End,28.8200,-97.0000
      D,4,N Main @ E Oak (Southbound),28.8100,-97.0003
    CSV
    "routes.txt" => "route_id,route_short_name,route_long_name,route_color,route_text_color,route_sort_order\n1,1,Pink,F804C1,FFFFFF,1\n",
    "trips.txt" => <<~CSV,
      trip_id,route_id,service_id,trip_headsign,direction_id,block_id,shape_id
      n1,1,weekday,North End,0,B1,up
      s1,1,weekday,Rio Grande @ Base,1,B1,down
      n2,1,weekday,North End,0,B1,up
    CSV
    "stop_times.txt" => <<~CSV,
      trip_id,stop_sequence,stop_id,arrival_time,departure_time,shape_dist_traveled
      n1,0,A,08:00:00,08:00:00,0
      n1,1,B,08:10:00,08:10:00,1112
      n1,2,C,08:20:00,08:20:00,2224
      s1,0,C,08:30:00,08:30:00,0
      s1,1,D,08:40:00,08:40:00,1112
      s1,2,A,08:50:00,08:50:00,2224
      n2,0,A,09:00:00,09:00:00,0
      n2,1,B,09:10:00,09:10:00,1112
      n2,2,C,09:20:00,09:20:00,2224
    CSV
    "shapes.txt" => <<~CSV,
      shape_id,shape_pt_sequence,shape_pt_lat,shape_pt_lon,shape_dist_traveled
      up,0,28.8000,-97.0000,0
      up,1,28.8200,-97.0000,2224
      down,0,28.8200,-97.0003,0
      down,1,28.8000,-97.0003,2224
    CSV
    "calendar.txt" => "service_id,monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date\nweekday,1,1,1,1,1,0,0,20260101,20271231\n",
    "calendar_dates.txt" => "service_id,date,exception_type\nweekday,20261012,2\n",
    "fare_attributes.txt" => "fare_id,price\nadult,1.00\n"
  }.freeze

  let(:schedule) { FixedRouteSchedule.new(FEED) }
  let(:wed)      { Time.zone.parse("2026-09-30 08:05") }   # a Wednesday
  def next_bus(now, buses = {}) = described_class.new(schedule: schedule, buses: buses, now: now)
  def bus(lat, lon) = LiveBuses::Bus.new(unit: "1742", route_id: "1", lat: lat, lon: lon, at: Time.current)

  it "finds the caller by the stop names, whichever way round the corner is said" do
    %w[oak\ and\ main main\ &\ oak Main\ St\ at\ Oak].each do |said|
      expect(next_bus(wed).find_places(said).first).to include(label: "N Main @ E Oak", how: "stop")
    end
  end

  it "lists the next buses at the nearest stops, with a sentence to read out" do
    r = next_bus(wed).at(28.8101, -97.0001, "Main & Oak")
    north = r[:stops].find { |s| s[:id] == "B" }[:routes].first
    expect(north).to include(route: "Pink", headsign: "North End")
    expect(north[:buses].map { |b| b[:at].strftime("%H:%M") }).to eq %w[08:10 09:10]
    expect(north[:buses].first).to include(live: false, in_min: 5)
    expect(r[:say]).to eq "The next Pink bus toward North End, from the stop at N Main and E Oak, northbound side, is at 8:10 AM, in about 5 minutes."
  end

  it "counts the end of the line when the bus heads back from somewhere else, and knows the last bus" do
    r = next_bus(wed).at(28.8200, -97.0000, "North End")
    row = r[:stops].find { |s| s[:id] == "C" }[:routes]
    # n1 ends at C at 8:20 and s1 starts at C: that departure is listed, not the arrival
    expect(row.map { |g| [g[:headsign], g[:buses].map { |b| b[:at].strftime("%H:%M") }] }).to include(["Rio Grande @ Base", ["08:30"]])
    expect(row.flat_map { |g| g[:buses] }.find { |b| b[:at].strftime("%H:%M") == "08:30" }[:last]).to be true
  end

  it "rolls over to the next service day, skipping weekends and holidays" do
    sat = next_bus(Time.zone.parse("2026-10-03 10:00")).at(28.81, -97.0, "x")[:stops].find { |s| s[:id] == "B" }
    expect(sat[:routes].first[:buses].first).to include(tomorrow: true, day: Date.new(2026, 10, 5))
    hol = next_bus(Time.zone.parse("2026-10-12 07:00")).at(28.81, -97.0, "x")[:stops].find { |s| s[:id] == "B" }
    expect(hol[:routes].first[:buses].first[:day]).to eq Date.new(2026, 10, 13)
  end

  it "uses the live bus: how late it is, how many stops away, and not a stop it has passed" do
    # 8:12, the bus is only a quarter of the way up (timetable: 8:05), so 7 min late
    live = next_bus(Time.zone.parse("2026-09-30 08:12"), { "1" => bus(28.8050, -97.0000) })
    b = live.at(28.8101, -97.0001, "x")[:stops].find { |s| s[:id] == "B" }[:routes].first[:buses].first
    expect(b).to include(live: true, unit: "1742", delay_min: 7, stops_away: 0)
    expect(b[:at].strftime("%H:%M")).to eq "08:17"
    # past B already: the 8:10 is gone even though the clock hasn't passed it by much
    gone = next_bus(Time.zone.parse("2026-09-30 08:11"), { "1" => bus(28.8150, -97.0000) })
    times = gone.at(28.8101, -97.0001, "x")[:stops].find { |s| s[:id] == "B" }[:routes].first[:buses].map { |x| x[:at].strftime("%H:%M") }
    expect(times.first).to eq "09:10"
  end

  it "ignores a bus that isn't on its route's line" do
    far = next_bus(Time.zone.parse("2026-09-30 08:05"), { "1" => bus(28.9, -97.2) })
    b = far.at(28.8101, -97.0001, "x")[:stops].find { |s| s[:id] == "B" }[:routes].first[:buses].first
    expect(b[:live]).to be false
  end
end

RSpec.describe LiveBuses do
  it "keeps the freshest bus per route and drops ones not heard from lately" do
    rows = [
      { "unit" => "1769", "route_id" => "2", "lat" => 28.8, "lon" => -97.0, "gps_time" => 3.months.ago.iso8601 },
      { "unit" => "1768", "route_id" => "2", "lat" => 28.8, "lon" => -97.0, "gps_time" => 1.minute.ago.iso8601 },
      { "unit" => "1700", "route_id" => nil, "lat" => 28.8, "lon" => -97.0, "gps_time" => 1.minute.ago.iso8601 }
    ]
    expect(described_class.parse(rows).transform_values(&:unit)).to eq("2" => "1768")
  end
end

RSpec.describe NextBusController, type: :controller do
  include ActiveSupport::Testing::TimeHelpers
  login_admin_as_current_user

  it "is GCRPC's: other agencies get no Next Bus" do
    stub_const("ApplicationHelper::NEXT_BUS_PROVIDER_IDS", [0])
    get :lookup, params: { q: "oak" }
    expect(response.status).not_to eq 200
    expect(response.body).not_to include "stops"
  end

  it "answers a lookup as JSON with clock times" do
    stub_const("ApplicationHelper::NEXT_BUS_PROVIDER_IDS", [@current_user.current_provider.id])
    allow(FixedRouteSchedule).to receive(:current).and_return(FixedRouteSchedule.new(FEED))
    allow(LiveBuses).to receive(:current).and_return({})
    travel_to(Time.zone.parse("2026-09-30 08:05")) { get :lookup, params: { q: "main and oak" } }
    body = JSON.parse(response.body)
    expect(body["place"]["label"]).to eq "N Main @ E Oak"
    expect(body["stops"].first["routes"].first["buses"].first).to include("clock" => "8:10 AM", "in_min" => 5)
    expect(body["say"]).to start_with "The next Pink bus"
  end
end
