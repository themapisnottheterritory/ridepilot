require "rails_helper"

RSpec.describe AddressesController, type: :controller do
  login_admin_as_current_user

  # This should return the minimal set of attributes required to create a valid
  # Address. As you add validations to Address, be sure to
  # adjust the attributes here as well.
  let(:valid_attributes) {
    attributes_for(:address)
  }

  let(:invalid_attributes) {
    attributes_for(:address, :state => "", :address => '', :city => '')
  }

  describe "GET #trippable_autocomplete" do
    # Sticking to high-level testing of this action since there's otherwise a 
    # lot of setup involved.
    
    let(:autocomplete_terms) {
      {
        :term => "foooo",
        :format => "json"
      }
    }

    # MapRequest API now requires a key, current call without key causes HTTP error, so skip for now
    it "responds with JSON" do
      post :trippable_autocomplete, params: autocomplete_terms
      expect(response.content_type).to start_with("application/json")
    end

    it "include matching address info in the json response" do
      address = create(:provider_common_address, 
        :provider => @current_user.current_provider, 
        :name => "foooo",
        :the_geom => RGeo::Geographic.spherical_factory(srid: 4326).point(100, 30)
        )
      post :trippable_autocomplete, params: autocomplete_terms
      json = JSON.parse(response.body)
      expect(json).to be_a(Array)
      expect(json.first["id"]).to be_a(Integer)
      expect(json.first["id"]).to eq(address.id)
    end
  end
end
