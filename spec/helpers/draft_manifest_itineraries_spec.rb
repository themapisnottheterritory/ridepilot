require "rails_helper"

# Printing an unpublished run printed an empty table (Kristie, 2026-09-29);
# it now prints the working stops.
RSpec.describe DispatchHelper, "draft_manifest_itineraries", type: :helper do
  it "keeps the trip stops in order, without run start/end or a cancelled trip's drop-off" do
    ok = double(trip_result: nil)
    cancelled = double(trip_result: double(code: "CANC"))
    stops = [double(trip: nil, leg_flag: 0), double(trip: ok, leg_flag: 1), double(trip: cancelled, leg_flag: 1),
             double(trip: ok, leg_flag: 2), double(trip: cancelled, leg_flag: 2), double(trip: nil, leg_flag: 3)]
    allow(helper).to receive(:get_itineraries).and_return(stops)
    expect(helper.draft_manifest_itineraries(:run)).to eq [stops[1], stops[2], stops[3]]
  end
end
