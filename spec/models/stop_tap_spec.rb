require "rails_helper"

RSpec.describe StopTap do
  let(:itin) { double(id: 42) }

  it "records the app's tap time, arrival, position and version" do
    t = StopTap.record(itin, "pickup", ActionController::Parameters.new(at: 1.minute.ago.iso8601, lat: "28.8", lon: "-97.0", accuracy: "6.4", app: "1.0.31"))
    expect([t.itinerary_id, t.action, t.latitude, t.accuracy_m, t.app_version]).to eq [42, "pickup", 28.8, 6, "1.0.31"]
    expect(t).to be_online
  end

  it "keeps the tap when the position is missing or nonsense" do
    t = StopTap.record(itin, "arrive", ActionController::Parameters.new(lat: "abc", lon: "999"))
    expect(t.latitude).to be_nil
    expect(t.tapped_at).to be_nil
    expect(t).not_to be_online   # older app: no tap time, never counted as online
  end

  it "treats a tap that arrived long after it was made as made offline" do
    t = StopTap.create!(itinerary_id: 1, action: "pickup", tapped_at: 30.minutes.ago, received_at: Time.current)
    expect(t).not_to be_online
  end

  it "ignores actions it doesn't know" do
    expect(StopTap.record(itin, "undo", ActionController::Parameters.new)).to be_nil
  end

  it "keeps when the GPS fix was taken, and only trusts a fix close enough to the tap" do
    at = Time.current.change(usec: 0)
    t = StopTap.record(itin, "pickup", ActionController::Parameters.new(at: at.iso8601, lat: "28.8", lon: "-97.0", accuracy: "9", fix_at: (at - 200).iso8601))
    expect(t.fix_age).to eq 200
    expect(t.position_within?(300)).to be true    # good enough to learn where drivers stop
    expect(t.position_within?(60)).to be false    # too old to say the tablet was at the depot
  end

  it "doesn't trust a position with no fix time" do
    t = StopTap.record(itin, "pickup", ActionController::Parameters.new(at: Time.current.iso8601, lat: "28.8", lon: "-97.0", accuracy: "9"))
    expect(t.position_within?(300)).to be false
  end
end
