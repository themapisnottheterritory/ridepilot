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
end
