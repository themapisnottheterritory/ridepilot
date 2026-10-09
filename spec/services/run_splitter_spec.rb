require "rails_helper"

# Split shifts, 2026-10-09: a driver on UDR in the morning and DeWitt in the afternoon.
RSpec.describe RunSplitter do
  let(:day) { Date.current + 1 }
  let(:provider) { create(:provider) }
  let(:t) { ->(hm) { Time.zone.parse("#{day} #{hm}") } }
  let(:allen) { create(:driver, provider: provider) }
  let(:other) { create(:driver, provider: provider) }
  let(:bus) { create(:vehicle, provider: provider) }
  let(:udr) do
    create(:run, name: "UDR5", provider: provider, date: day, driver: allen, vehicle: bus,
           scheduled_start_time: t["08:00"], scheduled_end_time: t["17:00"])
  end
  let(:dewitt) do
    create(:run, name: "DeWitt1", provider: provider, date: day, driver: other, vehicle: create(:vehicle, provider: provider),
           scheduled_start_time: t["07:00"], scheduled_end_time: t["16:00"])
  end

  def trip_on(run, pickup, dropoff)
    create(:trip, provider: provider, customer: create(:customer, provider: provider),
           pickup_time: t[pickup], appointment_time: dropoff && t[dropoff]).tap do |trip|
      trip.update_columns(run_id: run.id)
      run.reload.add_trip_manifest!(trip.id)
    end
  end

  it "cuts the run, moves the later trips in order, and frees the driver for another afternoon run" do
    dewitt
    relief = create(:driver, provider: provider)
    early = trip_on(udr, "09:00", "09:30")
    late1 = trip_on(udr, "13:00", "13:20")
    late2 = trip_on(udr, "12:30", "12:50")

    splitter = RunSplitter.new(udr, at: "12:30", name: "UDR5 PM", driver_id: relief.id, vehicle_id: bus.id)
    expect(splitter.call).to be(true), splitter.errors.inspect

    pm = splitter.new_run
    expect(udr.reload.scheduled_end_time).to eq t["12:30"]
    expect([pm.name, pm.date, pm.scheduled_start_time, pm.scheduled_end_time, pm.driver, pm.vehicle])
      .to eq ["UDR5 PM", day, t["12:30"], t["17:00"], relief, bus]
    expect(early.reload.run).to eq udr
    expect([late1.reload.run, late2.reload.run]).to eq [pm, pm]
    expect(pm.manifest_order).to eq ["trip_#{late2.id}_leg_1", "trip_#{late2.id}_leg_2", "trip_#{late1.id}_leg_1", "trip_#{late1.id}_leg_2"]
    expect(udr.manifest_order).to eq ["trip_#{early.id}_leg_1", "trip_#{early.id}_leg_2"]
    expect(udr.itineraries.where(trip_id: [late1.id, late2.id])).to be_empty
    expect(pm.itineraries.where(trip_id: late1.id).count).to eq 2

    # Allen can now take DeWitt in the afternoon
    dewitt_pm = RunSplitter.new(dewitt, at: "13:15", name: "DeWitt1 PM", driver_id: allen.id, vehicle_id: dewitt.vehicle_id)
    expect(dewitt_pm.call).to be(true), dewitt_pm.errors.inspect
    expect(dewitt_pm.new_run.driver).to eq allen
  end

  it "refuses a time that leaves a rider on board" do
    trip_on(udr, "12:00", "12:45")
    splitter = RunSplitter.new(udr, at: "12:30", name: "UDR5 PM", driver_id: other.id)
    expect(splitter.call).to be false
    expect(splitter.errors.join).to include("picked up at 12:00 PM and dropped off at 12:45 PM")
    expect(udr.reload.scheduled_end_time).to eq t["17:00"]
    expect(Run.where(name: "UDR5 PM")).to be_empty
  end

  it "rolls back when the new driver is busy then" do
    dewitt
    splitter = RunSplitter.new(udr, at: "12:30", name: "UDR5 PM", driver_id: other.id)
    expect(splitter.call).to be false
    expect(splitter.errors).to eq ["#{other.name} is on DeWitt1 (7:00 AM - 4:00 PM) then."]
    expect(udr.reload.scheduled_end_time).to eq t["17:00"]
    expect(Run.where(name: "UDR5 PM")).to be_empty
  end

  it "refuses a time outside the run and a trip already picked up" do
    expect(RunSplitter.new(udr, at: "17:30", name: "X").tap(&:call).errors.join).to include("Split between")
    started = trip_on(udr, "14:00", "14:30")
    udr.itineraries.where(trip_id: started.id, leg_flag: 1).update_all(finish_time: Time.current)
    expect(RunSplitter.new(udr, at: "12:30", name: "X").tap(&:call).errors.join).to include("already been picked up")
  end

  it "leaves the new run without a driver when none is picked" do
    splitter = RunSplitter.new(udr, at: "12:30", name: "UDR5 PM")
    expect(splitter.call).to be true
    expect(splitter.new_run.driver).to be_nil
  end
end
