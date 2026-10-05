require "rails_helper"

# Editing a linked outbound subscription put today's date on its times while the
# return kept the date it was saved, so "8:30 AM today" counted as later than
# "4:00 PM last month" and every edit was refused (2026-10-05).
RSpec.describe RepeatingTrip, "linked outbound and return times" do
  let(:start) { Date.current.next_occurring(:monday) }
  let(:outbound) do
    create(:repeating_trip, start_date: start, direction: :outbound,
           pickup_time: Time.zone.parse("2026-08-25 08:00"), appointment_time: Time.zone.parse("2026-08-25 08:30"))
  end
  let!(:ret) do
    create(:repeating_trip, start_date: start, direction: :return, customer: outbound.customer, provider: outbound.provider,
           pickup_time: Time.zone.parse("2026-08-25 16:00"), appointment_time: nil, outbound_trip: outbound)
  end

  it "accepts an outbound edit whose times now carry a later date" do
    outbound.reload.assign_attributes(pickup_time: "08:00 AM", appointment_time: "08:30 AM")   # as the form sends them
    expect(outbound.appointment_time.to_date).to eq Date.current
    outbound.valid?
    expect(outbound.errors[:base].join).not_to match(/later than return/i)
  end

  it "still refuses an appointment after the return pickup (by clock time)" do
    outbound.reload.assign_attributes(pickup_time: "04:00 PM", appointment_time: "04:30 PM")
    outbound.valid?
    expect(outbound.errors[:base]).not_to be_empty
  end
end
