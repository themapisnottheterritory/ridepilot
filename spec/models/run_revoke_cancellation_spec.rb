require "rails_helper"

# Runs page, "Revoke cancellation" (2026-10-01): Heather cancelled two dozen
# Lavaca runs for late October and needed a way back.
RSpec.describe Run, "#revoke_cancellation!" do
  let(:date)   { Date.current.next_occurring(:monday) }
  let(:rrun)   { create(:repeating_run) }
  let(:run)    { create(:run, provider: rrun.provider, repeating_run: rrun, date: date, cancelled: true) }
  let(:rtrip)  { create(:repeating_trip, provider: rrun.provider) }
  let!(:assignment) { create(:weekday_assignment, repeating_trip: rtrip, repeating_run: rrun, wday: date.wday) }
  let!(:trip)  { create(:trip, provider: rrun.provider, repeating_trip: rtrip, run: nil, pickup_time: date.in_time_zone.change(hour: 9)) }

  it "takes the Cancelled mark off and puts that weekday's recurring trips back, with stops" do
    expect(run.revoke_cancellation!).to eq 1
    expect(run.reload.cancelled).to be false
    expect(trip.reload.run_id).to eq run.id
    expect(run.itineraries.where(trip_id: trip.id).count).to eq 2
  end

  it "leaves a trip that was cancelled, or already put on another run, where it is" do
    other = create(:run, provider: rrun.provider, date: date)
    trip.update_column(:run_id, other.id)
    expect(run.revoke_cancellation!).to eq 0
    expect(trip.reload.run_id).to eq other.id
  end

  it "leaves a started run alone" do
    run.update_columns(actual_start_time: Time.current)
    expect(run.revoke_cancellation!).to be_nil
    expect(run.reload.cancelled).to be true
  end
end
