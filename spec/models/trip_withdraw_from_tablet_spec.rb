require "rails_helper"

# A cancelled or deleted trip comes off the driver's tablet at once, without
# waiting for dispatch to Publish (2026-10-01: four runs carried cancelled or
# deleted trips on their tablets all morning).
RSpec.describe Trip, "leaving the driver's tablet" do
  let(:run)   { create(:run, date: Date.current) }
  let(:trip)  { create(:trip, run: run, provider: run.provider, pickup_time: Time.current.change(hour: 9), appointment_time: Time.current.change(hour: 9, min: 30)) }
  let(:other) { create(:trip, run: run, provider: run.provider, pickup_time: Time.current.change(hour: 10), appointment_time: Time.current.change(hour: 10, min: 30)) }

  before do
    [trip, other].each do |t|
      [1, 2].each do |leg|
        itin = Itinerary.create!(run: run, trip: t, leg_flag: leg, time: leg == 1 ? t.pickup_time : t.appointment_time, address: t.pickup_address)
        PublicItinerary.create!(run: run, itinerary: itin, sequence: PublicItinerary.where(run_id: run.id).count)
      end
    end
  end

  def published_trip_ids
    PublicItinerary.where(run_id: run.id).map { |p| p.itinerary&.trip_id }
  end

  def result(code)
    TripResult.find_by(code: code) || create(:trip_result, code: code, name: code)
  end

  it "takes a cancelled trip's stops off at once and tells the tablet" do
    expect(ManifestNotificationWorker).to receive(:perform_async).with(run.id)
    trip.update!(trip_result: result("CANC"))
    expect(published_trip_ids).to eq [other.id, other.id]
  end

  it "takes a deleted trip's stops off" do
    trip.destroy
    expect(published_trip_ids).to eq [other.id, other.id]
  end

  it "keeps a no-show on the tablet: the driver recorded it there" do
    trip.update!(trip_result: result("NS"))
    expect(published_trip_ids).to eq [trip.id, trip.id, other.id, other.id]
  end

  it "keeps a pickup the driver already finished" do
    trip.itineraries.find_by(leg_flag: 1).update_column(:finish_time, Time.current)
    trip.update!(trip_result: result("CANC"))
    expect(published_trip_ids).to eq [trip.id, other.id, other.id]
  end

  it "leaves other edits for Publish" do
    trip.update!(notes: "gate code 1234")
    expect(published_trip_ids.count(trip.id)).to eq 2
  end
end
