require "rails_helper"

# Tap check (2026-10-04): no false positives. A run is listed only for taps that
# were proven made online; dead zones, re-syncs, wrong clocks, older apps and
# riders at one place never put a run on the list.
RSpec.describe TapCheck do
  let(:day) { Date.current - 1 }
  let(:run) { create(:run, date: day, name: "R12", scheduled_start_time: day.in_time_zone.change(hour: 7), scheduled_end_time: day.in_time_zone.change(hour: 17)) }
  let(:t0) { day.in_time_zone.change(hour: 14) }
  # three homes about 1 km apart, and two flats at one complex
  let(:places) { [[28.80, -97.00], [28.81, -97.00], [28.82, -97.00]] }

  def home(lat, lon)
    create(:address, type: "CustomerCommonAddress", provider: run.provider, the_geom: Address.compute_geom(lat, lon))
  end

  def stop!(address, at, received: nil, app_time: true)
    trip = create(:trip, provider: run.provider, run: run, pickup_time: at, appointment_time: at + 30.minutes)
    i = Itinerary.create!(run: run, trip: trip, leg_flag: 1, address_id: address.id, time: at,
                          finish_time: at, status_code: Itinerary::STATUS_COMPLETED)
    StopTap.create!(itinerary_id: i.id, action: "pickup", tapped_at: (app_time ? at : nil), received_at: received || at + 2.seconds)
    i
  end

  def report = TapCheck.day(day, provider_ids: [run.provider_id]).find { |r| r.run.id == run.id }

  it "lists three stops at different places tapped within a minute, online" do
    places.each_with_index { |(la, lo), k| stop!(home(la, lo), t0 + k * 20.seconds) }
    r = report
    expect(r.burst_stops).to eq 3
    expect(r).to be_issues
  end

  it "doesn't list riders at one complex picked up together" do
    a = home(28.80, -97.00); b = home(28.8001, -97.0001); c = home(28.8002, -97.0)
    [a, b, c].each_with_index { |x, k| stop!(x, t0 + k * 20.seconds) }
    expect(report.burst_stops).to eq 0
  end

  it "doesn't list taps made in a dead zone and sent later (they keep their own times)" do
    places.each_with_index { |(la, lo), k| stop!(home(la, lo), t0 + k * 12.minutes, received: t0 + 40.minutes + k.seconds) }
    expect(report.burst_stops).to eq 0
  end

  it "doesn't list a burst it can't prove was made online (arrived late)" do
    places.each_with_index { |(la, lo), k| stop!(home(la, lo), t0 + k * 20.seconds, received: t0 + 30.minutes) }
    r = report
    expect(r.burst_stops).to eq 0
    expect(r.unchecked).to eq 1
  end

  it "doesn't list taps from an app too old to send its own tap time" do
    places.each_with_index { |(la, lo), k| stop!(home(la, lo), t0 + k * 20.seconds, app_time: false) }
    expect(report.burst_stops).to eq 0
  end

  it "doesn't list stops never tapped when the tablet may still be holding them" do
    trip = create(:trip, provider: run.provider, run: run, pickup_time: t0, appointment_time: t0 + 30.minutes)
    Itinerary.create!(run: run, trip: trip, leg_flag: 1, address_id: home(28.8, -97.0).id, time: t0, status_code: 0)
    expect(report.not_tapped).to eq 0   # no tablet report after the day: can't tell
  end

  it "keeps burst stops out of where drivers stop" do
    its = places.each_with_index.map { |(la, lo), k| stop!(home(la, lo), t0 + k * 20.seconds) }
    expect(TapCheck.burst_ids(its)).to match_array(its.map(&:id))
  end
end
