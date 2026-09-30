require "rails_helper"

# Ask RidePilot "add a saved place": what the card says before anyone clicks.
RSpec.describe SavedPlaceProposal do
  let(:provider) { create(:provider) }
  let(:admin)    { create(:admin, current_provider: provider) }
  let!(:medical) { AddressGroup.find_by(name: "Medical") || AddressGroup.create!(name: "Medical") }

  def hit(number, lat, lon)
    { "lat" => lat.to_s, "lon" => lon.to_s, "address" => { "house_number" => number } }
  end

  # the map server answers: search by fields, free text, then the town
  def map_answers(*answers)
    allow_any_instance_of(described_class).to receive(:nominatim).and_return(*answers)
  end

  it "reads the request, finds the pin and the category, and warns about nothing" do
    map_answers([hit("311", 28.83, -97.01)], [hit("0", 28.80, -97.00)])
    p = described_class.new(provider: provider, user: admin, name: "VA Clinic", address: "311 Spring Green Blvd",
                            city: "victoria", state: "tx", zip: "77904", category: "Medical").check
    expect(p.to_h).to include(name: "VA Clinic", city: "Victoria", state: "TX", zip: "77904", address_group_id: medical.id,
                              pin: { lat: 28.83, lon: -97.01 }, on_map: true, warnings: [], existing: [], can_add: true)
    expect(p.summary).to include("**VA Clinic**, 311 Spring Green Blvd, Victoria 77904", "under Medical", "**Add it**")
  end

  it "opens the map on the town and asks for the pin when the map has no house number" do
    map_answers([hit("1", 28.9, -97.1)], [], [hit(nil, 28.80, -97.00)])
    p = described_class.new(provider: provider, user: admin, name: "VA Clinic", address: "311 Spring Green Blvd", city: "Victoria").check
    expect(p.to_h).to include(pin: nil, on_map: false, map_center: { lat: 28.8, lon: -97.0 })
    expect(p.warnings.first).to include "Drag the pin"
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
end
