require "rails_helper"

RSpec.describe TripScheduler do
  let(:day) { Date.current }
  # like a day's run generated from its template before dispatch staffs it: the
  # generator skips validation, so clear vehicle and driver the same way
  let(:run) do
    create(:run, name: "RVIC1", date: day,
           scheduled_start_time: Time.zone.parse("#{day} 08:00"), scheduled_end_time: Time.zone.parse("#{day} 17:00"))
      .tap { |r| r.update_columns(vehicle_id: nil, driver_id: nil) }
  end
  let(:trip) do
    create(:trip, pickup_time: Time.zone.parse("#{day} 07:00"), appointment_time: nil)
  end

  it "names the run, its day and hours in every refusal" do
    scheduler = TripScheduler.new(trip.id, run.id)
    scheduler.execute
    label = "RVIC1, #{day.strftime('%a %b %-d')}"
    expect(scheduler.errors.size).to eq(3)
    expect(scheduler.errors[0]).to include("#{label}, runs 8:00 AM - 5:00 PM; pickup is 7:00 AM")
    expect(scheduler.errors[1]).to end_with("(#{label})")
    expect(scheduler.errors[2]).to end_with("(#{label})")
    expect(trip.reload.run_id).to be_nil
  end
end
