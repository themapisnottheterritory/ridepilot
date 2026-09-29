require "rails_helper"

RSpec.describe ItinerarySerializer, "will call" do
  let(:trip) { t = build(:trip, notes: "Gate code 1234", will_call: true); t.save!(validate: false); t }

  def attrs(leg_flag)
    itin = Itinerary.new(trip: trip, leg_flag: leg_flag, run: build(:run), time: trip.pickup_time)
    described_class.new(itin).serializable_hash[:data][:attributes]
  end

  it "tells the driver first, on the pickup, keeping the trip's own notes" do
    a = attrs(1)
    expect(a[:will_call]).to be true
    expect(a[:trip_notes]).to eq "#{ItinerarySerializer::WILL_CALL_NOTE}\nGate code 1234"
  end

  it "leaves the drop-off, and trips that aren't will call, as they were" do
    expect(attrs(2).values_at(:will_call, :trip_notes)).to eq [false, "Gate code 1234"]
    trip.update_columns(will_call: false)
    expect(attrs(1).values_at(:will_call, :trip_notes)).to eq [false, "Gate code 1234"]
  end
end

RSpec.describe WillCallHelper, type: :helper do
  it "labels will-call trips only" do
    expect(helper.will_call_label(Trip.new(will_call: true))).to include("Will call")
    expect(helper.will_call_label(Trip.new)).to be_blank
  end
end

RSpec.describe "Will call carries from a subscription to its trips" do
  it "is copied like the subscription's other trip settings" do
    expect(RepeatingTrip.ride_coordinator_attributes).to include("will_call")
    expect(Trip.column_names).to include("will_call")
  end
end
