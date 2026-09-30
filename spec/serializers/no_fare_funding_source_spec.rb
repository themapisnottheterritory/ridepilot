require "rails_helper"

# A funding source that pays the whole ride (Lavaca's Title III riders, billed
# to New Horizons monthly): no fare quoted, none expected on the tablet.
RSpec.describe "No-fare funding sources" do
  let(:paid)  { FundingSource.create!(name: "Title III - New Horizons", no_fare: true, fare_note: "billed to New Horizons monthly") }
  let(:plain) { FundingSource.create!(name: "Rider fares") }
  let(:trip)  { t = build(:trip, notes: "Gate code 1234", funding_source: paid); t.save!(validate: false); t }

  def attrs(leg_flag)
    itin = Itinerary.new(trip: trip, leg_flag: leg_flag, run: build(:run), time: trip.pickup_time)
    ItinerarySerializer.new(itin).serializable_hash[:data][:attributes]
  end

  it "quotes no fare, saying who is billed, ahead of any amount typed on the trip" do
    trip.update_columns(fare_amount: 5)
    q = TripFareQuote.new(trip, compute_distance: false).call
    expect([q.no_fare, q.amount, q.basis]).to eq [true, 0, "No fare: billed to New Horizons monthly"]
  end

  it "prices the trip as usual under any other funding source" do
    trip.update_columns(funding_source_id: plain.id, fare_amount: 5)
    q = TripFareQuote.new(trip, compute_distance: false).call
    expect([q.no_fare, q.amount]).to eq [nil, 5]
  end

  it "tells the driver on the pickup, with no fare box, and leaves the drop-off alone" do
    a = attrs(1)
    expect(a[:trip_notes]).to eq "NO FARE: billed to New Horizons monthly. Don't collect a fare.\nGate code 1234"
    expect(a[:fare]).to be_nil
    expect(attrs(2)[:trip_notes]).to eq "Gate code 1234"
  end

  it "puts will call first, then no fare, then the trip's notes" do
    trip.update_columns(will_call: true)
    expect(attrs(1)[:trip_notes].lines.map(&:strip)).to eq [ItinerarySerializer::WILL_CALL_NOTE, "NO FARE: billed to New Horizons monthly. Don't collect a fare.", "Gate code 1234"]
  end
end
