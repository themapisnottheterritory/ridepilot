require "rails_helper"

# Goliad, 2026-10-06: revenue and non-revenue hours and miles by bus, from what
# drivers record (odometers, the run's start and end, stop times).
RSpec.describe VehicleSummaryReport do
  let(:provider) { create(:provider) }
  let(:garage)   { create(:garage_address, provider: provider) }
  let(:bus)      { create(:vehicle, provider: provider, name: "GOL 15", garage_address: garage) }
  let(:day)      { Date.current - 1 }
  let(:at)       { ->(h, m = 0) { Time.zone.local(day.year, day.month, day.day, h, m) } }
  # a fixed road distance per leg so the arithmetic is plain
  let(:road)     { ->(_from, _to) { 4.0 } }

  def closed_run(name:, start_odo: 1000, end_odo: 1050, start_at: at.(7), end_at: at.(15))
    run = create(:run, provider: provider, vehicle: bus, date: day, name: name)
    run.update_columns(start_odometer: start_odo, end_odometer: end_odo, actual_start_time: start_at, actual_end_time: end_at)
    run
  end

  def stop(run, leg, arrived: nil, done: nil)
    trip = create(:trip, provider: provider, run: run, pickup_time: at.(8), trip_result: TripResult.find_by(code: "COMP") || create(:trip_result, code: "COMP"))
    Itinerary.create!(run: run, trip: trip, leg_flag: leg, address: trip.pickup_address, arrival_time: arrived, finish_time: done)
  end

  def report(**opts)
    described_class.new(provider_ids: [provider.id], start_date: day, end_date: day + 1, distance: road, **opts).run!
  end

  it "splits a closed-out run's hours at the first pick-up and last drop-off, and its miles by the garage legs" do
    run = closed_run(name: "Rgol1")
    stop(run, 1, arrived: at.(7, 30), done: at.(7, 35))
    stop(run, 2, arrived: at.(14), done: at.(14, 30))
    r = report.rows.first
    expect(r).to be_counted
    expect(r.total_hours).to eq 8.0
    expect(r.revenue_hours).to eq 7.0          # 7:30 to 14:30
    expect(r.non_revenue_hours).to eq 1.0
    expect(r.odometer_miles).to eq 50
    expect(r.non_revenue_miles).to eq 8.0      # 4 out + 4 back
    expect(r.revenue_miles).to eq 42.0
    v = report.by_vehicle.first
    expect(v).to include(vehicle: "GOL 15", runs: 1, total_miles: 50.0, revenue_miles: 42.0, trips: 2)
  end

  it "lists a run that isn't closed out with what is missing, and leaves it out of the totals" do
    run = create(:run, provider: provider, vehicle: bus, date: day, name: "Rgol3")
    run.update_columns(start_odometer: 2000, actual_start_time: at.(8))
    stop(run, 1, arrived: at.(9), done: at.(9, 5))
    s = report
    expect(s.counted).to be_empty
    expect(s.not_counted.first.missing).to include("one odometer reading", "an end on the tablet (not closed out)")
    expect(s.totals[:runs]).to eq 0
  end

  it "flags odometer readings that can't be right" do
    run = closed_run(name: "Rgol2", start_odo: 31070, end_odo: 30979)
    stop(run, 1, arrived: at.(8), done: at.(8, 5))
    expect(report.not_counted.first.missing.join).to include("odometer readings that add up")
  end

  it "counts the run from the first stop when the driver started the run late on the tablet" do
    run = closed_run(name: "Rgol5", start_at: at.(9, 23), end_at: at.(15, 12))
    stop(run, 1, arrived: at.(8, 43), done: at.(8, 50))
    stop(run, 2, done: at.(15, 9))
    r = report.rows.first
    expect(r.start_at).to eq at.(8, 43)
    expect(r.non_revenue_hours).to be_within(0.001).of(3 / 60.0)
  end

  it "won't count a run whose garage on file can't be where the bus started" do
    run = closed_run(name: "MATA2", start_odo: 100, end_odo: 154)     # 54 miles on the odometer
    stop(run, 1, arrived: at.(8), done: at.(8, 5))
    r = described_class.new(provider_ids: [provider.id], start_date: day, end_date: day + 1, distance: ->(_f, _t) { 68.9 }).run!.rows.first
    expect(r).not_to be_counted
    expect(r.missing.first).to include("a garage that fits this run", "138 miles", "odometer shows 54")
  end

  it "leaves out runs with no trips and nothing recorded" do
    create(:run, provider: provider, vehicle: bus, date: day, name: "Unused")
    s = report
    expect(s.rows).to be_empty
    expect(s.empty_runs).to eq 1
  end
end
