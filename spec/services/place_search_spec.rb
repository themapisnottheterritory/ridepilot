require "rails_helper"
require "tmpdir"

# Azure Maps place lookup: what it accepts and what it refuses. Never calls
# Azure (request is stubbed); answers shaped like the real ones of 2026-10-05.
RSpec.describe PlaceSearch do
  let(:cuero) { { lat: 29.0938, lon: -97.2890 } }
  let(:diane) do
    { "type" => "POI", "poi" => { "name" => "Diane's Hair Salon" }, "position" => { "lat" => 29.09069, "lon" => -97.32402 },
      "address" => { "freeformAddress" => "2010 State Highway 72 West, Cuero, TX 77954", "streetNumber" => "2010" } }
  end
  let(:town) { { "type" => "Geography", "position" => { "lat" => 29.0938, "lon" => -97.2890 }, "address" => { "freeformAddress" => "Cuero, TX" } } }
  let(:far_namesake) do   # the right name, the wrong town (Tru-Skin in Bastrop for Hallettsville)
    { "type" => "POI", "poi" => { "name" => "Diane's Hair Salon" }, "position" => { "lat" => 30.11, "lon" => -97.32 }, "address" => {} }
  end
  let(:other_business) do
    { "type" => "POI", "poi" => { "name" => "Buc-ee's" }, "position" => { "lat" => 29.09, "lon" => -97.30 }, "address" => {} }
  end

  around do |ex|
    Dir.mktmpdir do |dir|
      @dir = dir
      ENV["AZURE_MAPS_KEY"] = "test-key"
      ex.run
    ensure
      ENV.delete("AZURE_MAPS_KEY")
    end
  end
  before { allow(described_class).to receive(:counter_path) { File.join(@dir, "count") } }

  def find(**opts)
    described_class.find(name: "Diane's Hair Salon", city: "Cuero", near: cuero, **opts)
  end

  it "takes the business with the name asked for, near the town" do
    allow(described_class).to receive(:request).and_return([town, diane])
    hit = find
    expect(hit.to_h).to include(kind: "business", name: "Diane's Hair Salon", lat: 29.09069, lon: -97.32402)
  end

  it "refuses the town centre, another business, and the right name in the wrong town" do
    allow(described_class).to receive(:request).and_return([town, other_business, far_namesake])
    expect(find).to be_nil
  end

  it "takes an address only when the house number is the one typed" do
    addr = { "type" => "Point Address", "position" => { "lat" => 29.0907, "lon" => -97.3245 },
             "address" => { "streetNumber" => "2010", "freeformAddress" => "2010 State Highway 72 W, Cuero" } }
    allow(described_class).to receive(:request).and_return([addr])
    expect(find(house_number: "2010")&.kind).to eq "address"
    expect(find(house_number: "1219")).to be_nil
    expect(find).to be_nil
  end

  it "matches names with small differences" do
    expect(described_class.same_name?("Day N Night Medical Supplies", "Day N Night Medical Supply")).to be true
    expect(described_class.same_name?("Tru-Skin Dermatology", "Tru Skin Derm")).to be true
    expect(described_class.same_name?("The Texan", "Texan")).to be true
    expect(described_class.same_name?("Buc-ee's", "Diane's Hair Salon")).to be false
    expect(described_class.same_name?("Dollar General", "Family Dollar")).to be false
  end

  it "does nothing without a key or without a town to check against" do
    expect(described_class).not_to receive(:request)
    expect(described_class.find(name: "Diane's Hair Salon", city: "Cuero", near: nil)).to be_nil
    ENV.delete("AZURE_MAPS_KEY")
    expect(find).to be_nil
  end

  it "stops at the monthly cap and tells the trouble board once" do
    allow(described_class).to receive(:monthly_cap).and_return(2)
    allow(described_class).to receive(:request).and_return([diane])
    expect(find).to be_present
    expect(find).to be_present
    expect { expect(find).to be_nil }.to change { TroubleEvent.where(action: "place_search").count }.by(1)
    expect { expect(find).to be_nil }.not_to(change { TroubleEvent.count })
    expect(described_class).to have_received(:request).twice
  end

  it "falls back quietly when Azure fails, and records it" do
    allow(described_class).to receive(:request).and_raise("Azure Maps answered 401")
    expect { expect(find).to be_nil }.to change { TroubleEvent.where(action: "place_search").count }.by(1)
  end
end

RSpec.describe SavedPlaceProposal, "with Azure Maps" do
  let(:provider) { create(:provider) }
  let(:admin)    { create(:admin, current_provider: provider) }
  let(:hit) do
    PlaceSearch::Result.new(lat: 29.09069, lon: -97.32402, name: "Diane's Hair Salon",
                            address: "2010 State Highway 72 West, Cuero, TX 77954", kind: "business")
  end

  def proposal(name: "Diane's Hair Salon")
    described_class.new(provider: provider, user: admin, name: name, address: "2010 State Highway 72 W", city: "Cuero", state: "TX", zip: "77954")
  end

  def map_gives(answer)   # our map: nothing by fields/text for the house; town centre on request
    allow_any_instance_of(described_class).to receive(:nominatim) do |_p, _path, params|
      params[:city] && !params[:street] && !params[:q] ? [{ "lat" => "29.0938", "lon" => "-97.2890", "address" => {} }] : answer
    end
  end

  it "asks Azure Maps when our map has no exact pin, and says where the pin came from" do
    map_gives([])
    expect(PlaceSearch).to receive(:find).with(hash_including(name: "Diane's Hair Salon", city: "Cuero", house_number: "2010")).and_return(hit)
    p = proposal.check
    expect(p.to_h).to include(pin: { lat: 29.09069, lon: -97.32402 }, pin_kind: "business", on_map: true)
    expect(p.warnings.first).to include("Found on Azure Maps", "check the pin")
    expect(p.to_h[:pin_label]).to eq(title: "Diane's Hair Salon", address: "2010 State Highway 72 West, Cuero, TX 77954",
                                     source: "Azure Maps · check it's the right building")
  end

  it "never second-guesses an exact pin from our map" do
    map_gives([{ "lat" => "29.0907", "lon" => "-97.3245", "osm_type" => "node", "address" => { "house_number" => "2010" } }])
    expect(PlaceSearch).not_to receive(:find)
    expect(proposal.check.to_h[:pin_kind]).to eq "exact"
  end

  it "doesn't ask about a bare address with no name" do
    map_gives([])
    expect(PlaceSearch).not_to receive(:find)
    proposal(name: nil).check
  end

  it "asks about a find by name with no address" do
    map_gives([])
    expect(PlaceSearch).to receive(:find).with(hash_including(name: "Hallettsville Rehab & Nursing", city: "Hallettsville")).and_return(nil)
    described_class.new(provider: provider, user: admin, name: "Hallettsville Rehab & Nursing", address: "Hallettsville Rehab & Nursing",
                        city: "Hallettsville", state: "TX", mode: :find).check
  end

  it "doesn't spend a lookup on a place already saved under that name" do
    map_gives([])
    saved = instance_double(ProviderCommonAddress, name: "Day N Night Medical Supply", the_geom: "POINT(-96.98 28.81)",
                            id: 1, address: "2007 E Red River St", city: "Victoria")
    allow_any_instance_of(described_class).to receive(:find_existing).and_return([saved])
    expect(PlaceSearch).not_to receive(:find)
    p = described_class.new(provider: provider, user: admin, name: "Day N Night Medical Supply", address: nil, city: "Victoria", mode: :find).check
    expect(p.summary).to start_with("I couldn't find **Day N Night Medical Supply**, Victoria").or start_with("Here's **Day N Night Medical Supply**, Victoria")
    expect(p.summary).not_to include(", ,")
  end

  it "finds a saved place by name when a find carries the name as the address" do
    map_gives([])
    create(:provider_common_address, provider: provider, name: "Diane's Hair Salon", address: "2010 State Highway 72 W",
           city: "Cuero", state: "TX", the_geom: Address.compute_geom(29.0907, -97.3245))
    expect(PlaceSearch).not_to receive(:find)   # already saved and on the map: no lookup
    p = described_class.new(provider: provider, user: admin, name: "Diane's Hair Salon", address: "Diane's Hair Salon", city: "Cuero", mode: :find).check
    expect(p.existing.map(&:name)).to include("Diane's Hair Salon")
  end

  # Phil, 2026-10-05: a bare blue pin gave nobody anything to check, and a find
  # by name saved a place with no address.
  it "fills the address from Azure Maps on a find by name, and labels the pin" do
    map_gives([])
    found = PlaceSearch::Result.new(lat: 29.1149, lon: -97.2942, name: "Kuecker Service Center", kind: "business",
                                    address: "250 Farm-to-Market 766, Cuero, TX 77954", street: "250 Farm-to-Market 766", city: "Cuero", zip: "77954")
    allow(PlaceSearch).to receive(:find).and_return(found)
    p = described_class.new(provider: provider, user: admin, name: "Kuecker service center", address: nil, city: "Cuero", mode: :find).check
    expect(p.to_h).to include(address: "250 Farm-to-Market 766", city: "Cuero", zip: "77954", pin_kind: "business")
    expect(p.to_h[:pin_label]).to include(title: "Kuecker Service Center", address: "250 Farm-to-Market 766, Cuero, TX 77954")
  end

  it "labels a pin from our own map with where it came from" do
    map_gives([{ "lat" => "29.0907", "lon" => "-97.3245", "osm_type" => "node", "address" => { "house_number" => "2010" } }])
    p = described_class.new(provider: provider, user: admin, name: "Diane's Hair Salon", address: "2010 TX 72", city: "Cuero", state: "TX", zip: "77954").check
    expect(p.to_h[:pin_label]).to eq(title: "Diane's Hair Salon", address: "2010 TX 72, Cuero 77954", source: "Our map · this building")
  end
end
