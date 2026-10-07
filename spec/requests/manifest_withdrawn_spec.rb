require "rails_helper"

# 2026-10-07, UDR drivers: a stop that leaves the run stays on the tablet,
# crossed out with why, instead of vanishing.
RSpec.describe "Manifest keeps withdrawn stops", type: :request do
  let(:run)    { create(:run, date: Date.current).tap { |r| r.driver.update_column(:provider_id, r.provider_id) } }
  let(:driver) { run.driver }
  let(:tablet) do
    driver.user.ensure_authentication_token; driver.user.save!
    { "X-User-Username" => driver.user.username, "X-User-Token" => driver.user.authentication_token }
  end

  def stop(trip, leg)
    itin = create(:itinerary, run: run, trip: trip, leg_flag: leg, status_code: 0)
    PublicItinerary.create!(run: run, itinerary: itin, sequence: PublicItinerary.where(run_id: run.id).count)
    itin
  end

  def manifest
    get "/api/v1/manifest", params: { run_id: run.id }, headers: tablet
    expect(response.status).to eq 200
    JSON.parse(response.body)
  end

  let(:mary) { create(:trip, provider: run.provider, run: run) }
  let(:joe)  { create(:trip, provider: run.provider, run: run) }
  let!(:mary_up)   { stop(mary, 1) }
  let!(:mary_down) { stop(mary, 2) }
  let!(:joe_up)    { stop(joe, 1) }

  it "sends nothing withdrawn while every stop is still there" do
    body = manifest
    expect(body["data"].size).to eq 3
    expect(body["withdrawn"]).to eq []
    expect(ManifestSeenStop.where(run_id: run.id).count).to eq 3
  end

  it "a cancelled trip's stops come back as withdrawn, with the result" do
    manifest
    PublicItinerary.where(itinerary_id: [mary_up.id, mary_down.id]).delete_all
    mary.update_columns(trip_result_id: TripResult.find_or_create_by!(code: "LTCANC") { |t| t.name = "Late Cancel" }.id, run_id: nil)
    body = manifest
    expect(body["data"].map { |d| d["id"].to_i }).to eq [joe_up.id]
    w = body["withdrawn"]
    expect(w.map { |x| x["leg_flag"] }).to match_array [1, 2]
    expect(w.first).to include("trip_id" => mary.id, "cause" => "cancelled", "reason" => "Late Cancel", "customer_name" => mary.customer.name)
  end

  it "a no-show's drop-off is withdrawn as a no-show, and its pick-up stays with the result code" do
    manifest
    ns = TripResult.find_or_create_by!(code: "NS") { |t| t.name = "No-show" }
    mary_up.update_columns(status_code: Itinerary::STATUS_OTHER, finish_time: Time.current)
    mary.update_column(:trip_result_id, ns.id)   # what the no-show tap does
    body = manifest
    up = body["data"].find { |d| d["id"].to_i == mary_up.id }
    expect(up["attributes"]["trip_result_code"]).to eq "NS"
    expect(body["withdrawn"]).to contain_exactly(hash_including("trip_id" => mary.id, "leg_flag" => 2, "cause" => "no_show", "reason" => "No-show"))
  end

  it "a trip moved to another run says where" do
    manifest
    other = create(:run, date: Date.current, provider: run.provider, name: "UDR 4")
    PublicItinerary.where(itinerary_id: joe_up.id).delete_all
    joe.update_column(:run_id, other.id)
    expect(manifest["withdrawn"]).to contain_exactly(hash_including("trip_id" => joe.id, "cause" => "moved", "reason" => "Moved to UDR 4"))
  end

  it "a stop put back on the run is no longer withdrawn, even as a rebuilt itinerary" do
    manifest
    PublicItinerary.where(itinerary_id: joe_up.id).delete_all
    expect(manifest["withdrawn"].size).to eq 1
    stop(joe, 1)
    expect(manifest["withdrawn"]).to eq []
  end

  it "notes nothing for a run that isn't today's" do
    run.update_column(:date, Date.current + 1)
    expect(manifest["withdrawn"]).to eq []
    expect(ManifestSeenStop.count).to eq 0
  end
end
