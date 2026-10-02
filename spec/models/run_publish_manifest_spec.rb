require "rails_helper"

# Rgol1, 2026-10-02 (Andrew): the driver did the 11:00 and 12:45 trips early, then
# dispatch added trips for 9:00-11:00 and published -- and they never reached the
# tablet. Publish only sent the stops after the last finished one, and adding a
# trip slotted it among finished stops (a string-vs-integer compare never matched).
RSpec.describe Run, "#publish_manifest! with stops already finished" do
  let(:day)  { Time.zone.today }
  let(:run)  { create(:run, date: day, scheduled_start_time: day.in_time_zone.change(hour: 7), scheduled_end_time: day.in_time_zone.change(hour: 17)) }
  let(:at)   { ->(h, m = 0) { day.in_time_zone.change(hour: h, min: m) } }
  let!(:late) { create(:trip, provider: run.provider, run: run, pickup_time: at.(11), appointment_time: at.(11, 30)) }
  let!(:later) { create(:trip, provider: run.provider, run: run, pickup_time: at.(12, 15), appointment_time: at.(12, 45)) }

  before do
    run.reset_itineraries
    run.update_column(:manifest_order, run.sorted_itineraries.map(&:itin_id))
    run.publish_manifest!
    # the driver does both trips early, before 9:00
    run.itineraries.where(trip_id: [late.id, later.id]).update_all(finish_time: at.(8, 45))
    run.itineraries.where(leg_flag: 0).update_all(finish_time: at.(7))
  end

  def published_keys
    run.reload.public_itineraries.order(:sequence).map { |p| p.itinerary.itin_id }
  end

  it "puts a trip added before the last finished stop on the tablet" do
    added = create(:trip, provider: run.provider, run: run, pickup_time: at.(9), appointment_time: at.(9, 30))
    run.add_trip_itineraries!(added.id)
    run.add_trip_manifest!(added.id)
    Run.find(run.id).publish_manifest!   # Publish is its own click, with a fresh run

    keys = published_keys
    expect(keys).to include("trip_#{added.id}_leg_1", "trip_#{added.id}_leg_2")
    # after the stops already done, before the end of the run
    expect(keys.index("trip_#{added.id}_leg_1")).to be > keys.index("trip_#{later.id}_leg_2")
    expect(keys.last).to eq "run_end"
  end

  it "slots the new trip after the finished stops in the run's order" do
    added = create(:trip, provider: run.provider, run: run, pickup_time: at.(9), appointment_time: at.(9, 30))
    run.add_trip_itineraries!(added.id)
    run.add_trip_manifest!(added.id)
    order = run.reload.manifest_order
    expect(order.index("trip_#{added.id}_leg_1")).to be > order.index("trip_#{later.id}_leg_2")
  end

  it "doesn't publish a finished stop twice" do
    run.publish_manifest!
    keys = published_keys
    expect(keys.tally.values.max).to eq 1
  end
end
