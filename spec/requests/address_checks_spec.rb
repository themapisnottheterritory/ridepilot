require "rails_helper"

RSpec.describe "Address check page", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:staff) { create(:role, level: Role::EDITOR_LEVEL).user }
  before { sign_in staff }

  it "lists this agency's problems with a Fix link" do
    a = ProviderCommonAddress.create!(provider: staff.current_provider, address_group: create(:address_group), name: "Unpinned clinic", address: "2 Blank St", city: "Victoria", state: "TX", zip: "77901")
    get "/en/address_checks"
    expect(response).to be_successful
    expect(response.body).to include("No map pin", "Unpinned clinic", "/en/provider_common_addresses/#{a.id}/edit")
  end

  it "shows pins far from home on a map of the area we serve" do
    g = create(:address_group)
    30.times { |i| ProviderCommonAddress.create!(provider: staff.current_provider, address_group: g, name: "V#{i}", address: "#{i} Elm St", city: "Victoria", state: "TX", zip: "77901", the_geom: Address.compute_geom(28.80 + i * 0.0005, -97.00)) }
    away = ProviderCommonAddress.create!(provider: staff.current_provider, address_group: g, name: "Abroad", address: "1 Far Rd", city: "Victoria", state: "TX", zip: "77901")
    away.update_column(:the_geom, RGeo::Geographic.spherical_factory(srid: 4326).point(-84.0, 29.48))
    TownCentres.instance_variable_set(:@all, nil)
    get "/en/address_checks"
    expect(response.body).to include("ac-map", "Back to the service area", "Abroad", "\"town\":\"Victoria\"")
  ensure
    TownCentres.instance_variable_set(:@all, nil)
  end
end
