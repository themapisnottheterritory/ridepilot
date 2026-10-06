require "rails_helper"

RSpec.describe GarageFit do
  let(:provider) { create(:provider) }
  let(:victoria) { [28.80, -97.00] }
  let(:gonzales) { [29.50, -97.45] }   # ~55 miles from Victoria

  def garage(name, (lat, lon), city)
    GarageAddress.create!(provider: provider, name: name, address: "100 Yard Rd", city: city, state: "TX", zip: "77901",
                          the_geom: Address.compute_geom(lat, lon))
  end

  def bus(name, yard)
    create(:vehicle, provider: provider, name: name, garage_address: yard, active: true)
  end

  # a run on the bus, its first pick-up at `at`
  def run_on(vehicle, (lat, lon), city, date: Time.zone.today)
    run = create(:run, provider: provider, vehicle: vehicle, date: date)
    pick = create(:address, address: "1 First Stop St", city: city, state: "TX", the_geom: nil)
    pick.update_column(:the_geom, Address.compute_geom(lat, lon))
    create(:trip, provider: provider, run: run, pickup_address: pick, pickup_time: date.in_time_zone.change(hour: 8))
    run
  end

  it "finds a bus whose runs start far from its garage, around where they do start" do
    vct = garage("Victoria yard", victoria, "Victoria")
    far = bus("1785", vct)
    3.times { |i| run_on(far, gonzales, "Gonzales", date: Time.zone.today - i) }
    near = bus("1700", vct)
    run_on(near, [28.81, -97.01], "Victoria")
    found = described_class.buses
    expect(found.map(&:vehicle)).to eq [far]
    expect(found.first.median_miles).to be_between(50, 60)
    expect(found.first).to have_attributes(town: "Gonzales", runs: 3)
    expect(described_class.for_vehicle(near)).to be_nil
    expect(described_class.for_vehicle(far).vehicle).to eq far
  end

  it "finds a run still starting at the yard its bus used to live at, not the runs that follow the bus" do
    bay_city = garage("Bay City yard", [28.98, -95.95], "Bay City")
    r9 = bus("R9", bay_city)
    stale = run_on(r9, [28.99, -95.96], "Bay City", date: Time.zone.today - 4)
    old_yard = garage("Victoria yard", victoria, "Victoria")
    stale.update_columns(from_garage_address_id: old_yard.id, to_garage_address_id: old_yard.id)
    following = run_on(r9, [28.99, -95.96], "Bay City")   # took a copy of the bus's garage
    misfits = described_class.runs
    expect(misfits.map(&:run)).to eq [stale]
    expect(misfits.first.miles).to be > 60
    expect(described_class.buses).to be_empty
    expect(described_class.garages(following).first.the_geom.distance(bay_city.the_geom)).to be < 10
  end

  it "shows up on the nightly address check with a Fix link to the bus and to the run" do
    vct = garage("Victoria yard", victoria, "Victoria")
    far = bus("1785", vct)
    run_on(far, gonzales, "Gonzales")
    other = bus("R4", garage("Gonzales yard", gonzales, "Gonzales"))
    r = run_on(other, gonzales, "Gonzales")
    r.update_columns(from_garage_address_id: vct.id)
    k = AddressScan.new.by_kind
    expect(k["garage_far"].map(&:label).join).to include("Bus 1785")
    expect(AddressScan.fix_path(k["garage_far"].first)).to eq "/en/vehicles/#{far.id}/edit"
    expect(k["run_start_far"].map(&:detail).join).to match(/\d+ miles from its first stop in Gonzales/)
    expect(AddressScan.fix_path(k["run_start_far"].first)).to eq "/en/runs/#{r.id}/edit"
    pins = AddressScan.pins(k.values.flatten)
    expect(pins.map { |p| p[:kind] }).to include("garage_far", "run_start_far")
  end
end
