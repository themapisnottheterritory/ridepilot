require "rails_helper"

# Ask RidePilot "add a saved place": what the card says before anyone clicks.
RSpec.describe SavedPlaceProposal do
  let(:provider) { create(:provider) }
  let(:admin)    { create(:admin, current_provider: provider) }
  let!(:medical) { AddressGroup.find_by(name: "Medical") || AddressGroup.create!(name: "Medical") }

  def hit(number, lat, lon)
    { "lat" => lat.to_s, "lon" => lon.to_s, "address" => { "house_number" => number } }
  end

  # the map server answers in order: search by fields, free text, the street
  # alone (only when no house number matched), then the town
  def map_answers(*answers)
    allow_any_instance_of(described_class).to receive(:nominatim).and_return(*answers)
  end

  it "reads the request, finds the pin and the category, and warns about nothing" do
    map_answers([hit("311", 28.83, -97.01).merge("osm_type" => "node")], [hit("0", 28.80, -97.00)])
    p = described_class.new(provider: provider, user: admin, name: "VA Clinic", address: "311 Spring Green Blvd",
                            city: "victoria", state: "tx", zip: "77904", category: "Medical").check
    expect(p.to_h).to include(name: "VA Clinic", city: "Victoria", state: "TX", zip: "77904", address_group_id: medical.id,
                              pin: { lat: 28.83, lon: -97.01 }, pin_kind: "exact", on_map: true, warnings: [], existing: [], can_add: true, mode: "add")
    expect(p.summary).to include("**VA Clinic**, 311 Spring Green Blvd, Victoria 77904", "under Medical", "**Add it**")
  end

  it "opens the map on the town and says how to place the pin when the street isn't on the map" do
    # fields, free text, the street alone, the town
    map_answers([hit("1", 28.9, -97.1)], [], [], [hit(nil, 28.80, -97.00)])
    p = described_class.new(provider: provider, user: admin, name: "VA Clinic", address: "311 Spring Green Blvd", city: "Victoria").check
    expect(p.to_h).to include(pin: nil, pin_kind: nil, on_map: false, map_center: { lat: 28.8, lon: -97.0 })
    expect(p.warnings.first).to include("Spring Green Blvd isn't on our map yet", "Google Maps", "paste")
  end

  it "puts the pin on the street when the map knows the street but not the number" do
    map_answers([], [], [{ "lat" => "28.85", "lon" => "-96.99", "class" => "highway", "address" => {} }], [hit(nil, 28.80, -97.00)])
    p = described_class.new(provider: provider, user: admin, name: "X", address: "311 Main St", city: "Victoria").check
    expect(p.to_h).to include(pin: { lat: 28.85, lon: -96.99 }, pin_kind: "street", on_map: false)
    expect(p.warnings.first).to include("knows Main St but not number 311")
  end

  it "calls a number the map only estimates along the street an estimate, not a match" do
    estimate = hit("9999", 28.886, -96.995).merge("class" => "place", "type" => "house", "osm_type" => "way")
    map_answers([estimate], [hit(nil, 28.80, -97.00)])
    p = described_class.new(provider: provider, user: admin, name: "X", address: "9999 N Navarro St", city: "Victoria").check
    expect(p.to_h).to include(pin_kind: "estimate", on_map: true)
    expect(p.warnings.first).to include "estimates where number 9999 falls"
  end

  it "finds a landmark by name, worded as a lookup, and still offers to add it" do
    map_answers([{ "lat" => "28.878", "lon" => "-96.994", "address" => {} }], [hit(nil, 28.80, -97.00)])
    p = described_class.new(provider: provider, user: admin, name: "Walmart", address: "Navarro", city: "Victoria", mode: :find).check
    expect(p.to_h).to include(mode: "find", pin_kind: "landmark", pin: { lat: 28.878, lon: -96.994 }, can_add: true)
    expect(p.summary).to include("Here's **Walmart**, Navarro, Victoria on the map", "give it a name below")
  end

  it "says plainly when a find comes up empty" do
    map_answers([], [], [], [hit(nil, 28.80, -97.00)])
    p = described_class.new(provider: provider, user: admin, name: nil, address: "311 Spring Green Blvd", city: "Victoria", mode: :find).check
    expect(p.summary).to start_with "I couldn't find 311 Spring Green Blvd, Victoria on our map."
  end

  it "warns when the map's pin is far from the town typed" do
    map_answers([hit("311", 29.2, -97.5)], [hit(nil, 28.80, -97.00)])
    p = described_class.new(provider: provider, user: admin, name: "X", address: "311 Main St", city: "Victoria").check
    expect(p.warnings.first).to match(/\d+ miles from Victoria/)
  end

  it "lists what this agency already has at that number and street, or with that name" do
    map_answers([], [], [])
    create(:provider_common_address, provider: provider, name: "Vet Clinic", address: "311 Spring Green", city: "Victoria", address_group: medical)
    create(:provider_common_address, provider: provider, name: "VA Clinic old", address: "1908 N Laurent", city: "Victoria", address_group: medical)
    create(:provider_common_address, provider: create(:provider), name: "VA Clinic", address: "311 Spring Green Blvd", city: "Victoria", address_group: medical)
    p = described_class.new(provider: provider, user: admin, name: "VA Clinic", address: "311 Spring Green Blvd", city: "Victoria").check
    expect(p.existing.map(&:name)).to contain_exactly("Vet Clinic", "VA Clinic old")
    expect(p.summary).to include("Already saved and close to this", "not on the map")
  end

  it "shows no button to someone who may not add saved places" do
    map_answers([], [], [])
    user = create(:user, current_provider: provider)
    create(:role, user: user, provider: provider, level: 0)
    p = described_class.new(provider: provider, user: user, name: "X", address: "311 Main St", city: "Victoria").check
    expect(p.can_add?).to be false
    expect(p.warnings.last).to include "Only admins and editors"
    expect(p.summary).not_to include "**Add it**"
  end

  # Michelle, 2026-10-05: "2010 State Highway 72 W, Cuero" is just outside the
  # town limit, so the map gives it no town, and spells the road "TX 72".
  describe "an address on a numbered road outside the town" do
    let(:yorktown) { { "lat" => "28.9973", "lon" => "-97.4794", "address" => { "house_number" => "2010", "postcode" => "78164", "city" => "Yorktown" } } }
    let(:cuero)    { { "lat" => "29.0902", "lon" => "-97.3239", "address" => { "house_number" => "2010", "postcode" => "77954" } } }
    let(:kenedy)   { { "lat" => "28.7987", "lon" => "-97.8766", "address" => { "house_number" => "2010", "postcode" => "78119", "city" => "Kenedy" } } }

    def map_by_query
      allow_any_instance_of(described_class).to receive(:nominatim) do |_proposal, _path, params|
        if params[:city] && !params[:street] && !params[:q] then [{ "lat" => "29.0938", "lon" => "-97.2890", "address" => {} }]   # the town
        elsif params[:city] || params[:q].to_s.include?("Cuero") then []          # nothing inside the town
        elsif params[:street] == "2010 TX 72" || params[:q] == "2010 TX 72, TX" then [kenedy, yorktown, cuero]
        else []
        end
      end
    end

    it "asks in the map's spelling without the town and takes the one in the ZIP typed" do
      map_by_query
      p = described_class.new(provider: provider, user: admin, name: "Diane's Hair Salon", address: "2010 State Highway 72 W",
                              city: "Cuero", state: "TX", zip: "77954").check
      expect(p.to_h).to include(pin: { lat: 29.0902, lon: -97.3239 }, pin_kind: "exact", on_map: true)
    end

    it "takes the one nearest the town when no ZIP was typed" do
      map_by_query
      p = described_class.new(provider: provider, user: admin, name: "Diane's Hair Salon", address: "2010 State Highway 72 W",
                              city: "Cuero", state: "TX").check
      expect(p.to_h[:pin]).to eq(lat: 29.0902, lon: -97.3239)
    end
  end
end
