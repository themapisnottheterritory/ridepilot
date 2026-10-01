require "rails_helper"

# Named garages and moving a bus between them (2026-10-01).
RSpec.describe GarageMove do
  let(:provider) { create(:provider) }
  def garage(name, lat, lon) = GarageAddress.create!(provider: provider, name: name, address: "#{name} St", city: "Victoria", state: "TX", zip: "77901", the_geom: Address.compute_geom(lat, lon))
  let(:victoria) { garage("Victoria office", 28.8126, -96.9897) }
  let(:lavaca)   { garage("Port Lavaca yard", 28.6005, -96.6369) }
  let(:vehicle)  { create(:vehicle, provider: provider, garage_address: victoria) }

  it "moves the bus and the start and end of its upcoming runs, and their stops" do
    run = create(:run, provider: provider, vehicle: vehicle, date: Date.current + 1)
    run.update_columns(from_garage_address_id: nil, to_garage_address_id: nil)
    run.reset_itineraries
    result = GarageMove.new(vehicle, lavaca).call
    expect(result[:runs]).to eq 1
    expect(vehicle.reload.garage_address).to eq lavaca
    expect([run.reload.from_garage_address_id, run.to_garage_address_id]).to eq [lavaca.id, lavaca.id]
    expect(run.itineraries.where(leg_flag: [0, 3]).pluck(:address_id).uniq).to eq [lavaca.id]
  end

  it "also moves a run's copy of the old garage, but not a start dispatch set elsewhere, nor a started run" do
    copy = victoria.dup.tap { |c| c.name = nil; c.save! }
    elsewhere = GarageAddress.create!(provider: provider, address: "9 Other Rd", city: "Edna", state: "TX", zip: "77957", the_geom: Address.compute_geom(28.98, -96.64))
    run = create(:run, provider: provider, vehicle: vehicle, date: Date.current + 1)
    run.update_columns(from_garage_address_id: copy.id, to_garage_address_id: elsewhere.id)
    started = create(:run, provider: provider, vehicle: vehicle, date: Date.current)
    started.update_columns(from_garage_address_id: nil, to_garage_address_id: nil, actual_start_time: Time.current)
    GarageMove.new(vehicle, lavaca).call
    expect([run.reload.from_garage_address_id, run.to_garage_address_id]).to eq [lavaca.id, elsewhere.id]
    expect(started.reload.from_garage_address_id).to be_nil
  end

  it "links a run to a named garage when its bus is set, so the run follows later moves" do
    run = create(:run, provider: provider, date: Date.current + 2)
    run.update!(vehicle: vehicle)
    expect([run.from_garage_address_id, run.to_garage_address_id]).to eq [victoria.id, victoria.id]
  end

  describe GarageAddress do
    it "needs a name unique in the agency and a pin in the service area" do
      victoria
      dup = GarageAddress.new(provider: provider, name: "victoria OFFICE", address: "1 A St", city: "Victoria", state: "TX", zip: "77901", the_geom: Address.compute_geom(28.8, -96.9))
      expect(dup).not_to be_valid
      expect(dup.errors[:name].join).to include("already used")
      away = GarageAddress.new(provider: provider, name: "Abroad", address: "1 A St", city: "Victoria", state: "TX", zip: "77901", the_geom: Address.compute_geom(29.48, "9765114006172236".sub(/\A/, "-1")))
      expect(away).not_to be_valid
      expect(away.errors[:the_geom].join).to include("isn't on the map")
    end

    it "can't be retired while a bus uses it" do
      vehicle
      expect(victoria.retire!).to be false
      expect(lavaca.retire!).to be true
    end
  end
end
