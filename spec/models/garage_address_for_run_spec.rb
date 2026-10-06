require "rails_helper"

# A run takes its bus's garage as its start and end. A named garage is shared
# (the run follows the yard); copying it made another garage of the same name
# on the Garages list every time a run was created or closed (2026-10-06).
RSpec.describe GarageAddress, "#for_run" do
  let(:provider) { create(:provider) }
  def yard(name) = GarageAddress.create!(provider: provider, name: name, address: "1908 North Laurent Street", city: "Victoria", state: "TX", zip: "77901", the_geom: Address.compute_geom(28.81265, -96.9897))

  it "is the named garage itself, and a copy of a bus's own address" do
    named = yard("Victoria office")
    own = yard(nil)
    expect(named.for_run).to equal named
    copy = own.for_run
    expect(copy).to be_new_record
    expect(copy.address).to eq own.address
  end

  it "leaves no new garage of the same name when a run on the bus is completed" do
    named = yard("Victoria office")
    bus = create(:vehicle, provider: provider, garage_address: named)
    run = create(:run, provider: provider, vehicle: bus, date: Time.zone.today)
    run.update_columns(from_garage_address_id: nil, to_garage_address_id: nil)
    allow(RunDistanceCalculationWorker).to receive(:perform_async)
    expect { run.reload.set_complete! }.not_to change { GarageAddress.named.where(provider_id: provider.id).count }
    expect(run.reload.from_garage_address_id).to eq named.id
    expect(run.to_garage_address_id).to eq named.id
  end

  it "is what every place that gives a run its bus's garage uses" do
    sites = Dir[Rails.root.join("app/**/*.rb").to_s].select { |f| File.read(f) =~ /vehicle\S*garage_address\S*(\.try\(:dup\)|\.dup\b)|depot\.dup/ }
    expect(sites.map { |f| f.delete_prefix("#{Rails.root}/") }).to be_empty
  end
end
