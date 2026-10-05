require "rails_helper"

# Unticking days on a subscription withdraws the trips it already made on those
# days (Kelly, 2026-10-05), but never a trip with a result.
RSpec.describe RepeatingTrip, "when days are removed" do
  let(:monday) { Date.current.next_occurring(:monday) }
  let!(:sub) do   # saving generates its daily trips for the coming weeks
    create(:repeating_trip, start_date: monday, pickup_time: Time.zone.parse("#{monday} 08:00"), appointment_time: nil,
           repeats_mondays: true, repeats_tuesdays: true, repeats_wednesdays: true,
           repeats_thursdays: true, repeats_fridays: true)
  end
  let(:days) { ->(times) { times.map { |t| t.in_time_zone.strftime("%a") }.uniq.sort } }

  def remaining = sub.trips.reload.map(&:pickup_time)

  it "withdraws the future trips on the unticked days and says which" do
    expect(days.(remaining)).to eq %w[Fri Mon Thu Tue Wed]
    tue_thu = remaining.count { |t| t.in_time_zone.tuesday? || t.in_time_zone.thursday? }
    sub.repeats_tuesdays = false
    sub.repeats_thursdays = false
    sub.save!
    expect(days.(remaining)).to eq %w[Fri Mon Wed]
    expect(sub.withdrawn_trips.size).to eq tue_thu
    expect(days.(sub.withdrawn_trips)).to eq %w[Thu Tue]
    expect(Trip.only_deleted.where(repeating_trip_id: sub.id).count).to eq tue_thu   # soft-deleted, recoverable
  end

  it "keeps a trip on an unticked day that already has a result" do
    tue = sub.trips.order(:pickup_time).find { |t| t.pickup_time.in_time_zone.tuesday? }
    tue.update_columns(trip_result_id: create(:trip_result, code: "CANC").id)
    sub.repeats_tuesdays = false
    sub.save!
    expect(sub.trips.reload).to include(tue)
    expect(sub.withdrawn_trips).not_to include(tue.pickup_time)
  end

  it "withdraws nothing when no day is removed" do
    before = remaining.size
    sub.repeats_saturdays = true
    sub.save!
    expect(sub.withdrawn_trips).to be_empty
    expect(remaining.size).to be >= before
  end
end
