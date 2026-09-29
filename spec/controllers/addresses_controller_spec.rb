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

  describe "POST #validate_customer_specific on an existing customer address" do
    let(:saved) {
      CustomerCommonAddress.create!(address: "100 Main St", city: "Victoria", state: "TX", zip: "77901",
        provider_id: @current_user.current_provider.id, the_geom: Address.compute_geom(28.8, -97.0))
    }
    let(:fields) { {name: "Home", address: "100 Main St", city: "Victoria", state: "TX", zip: "77901"} }

    it "reports the pin kept when a unit number is appended and the dialog re-sends the current lat/lon" do
      post :validate_customer_specific, params: {prefix: "customer", address_id: saved.id, lat: 28.8, lon: -97.0,
        customer: fields.merge(address: "100 Main St Apt 5")}, format: :json
      body = JSON.parse(response.body)
      expect(body["success"]).to be true
      expect(body["attributes"]["address"]).to eq("100 Main St Apt 5")
      expect(body["attributes"]["latitude"]).to be_within(0.0001).of(28.8)
    end

    it "reports the pin dropped when the street changes without a new lat/lon" do
      post :validate_customer_specific, params: {prefix: "customer", address_id: saved.id,
        customer: fields.merge(address: "200 Other Rd")}, format: :json
      body = JSON.parse(response.body)
      expect(body["success"]).to be true
      expect(body["attributes"]["the_geom"]).to be_nil
    end

    it "reports the pin kept when only the name changes and no lat/lon is sent" do
      post :validate_customer_specific, params: {prefix: "customer", address_id: saved.id,
        customer: fields.merge(name: "Work")}, format: :json
      body = JSON.parse(response.body)
      expect(body["attributes"]["latitude"]).to be_within(0.0001).of(28.8)
    end
  end

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

    it "finds an address by street and city in any case" do
      address = create(:provider_common_address, provider: @current_user.current_provider, name: "Clinic",
        address: "600 Hospital Circle", city: "Bay City", state: "TX", zip: "77414",
        the_geom: RGeo::Geographic.spherical_factory(srid: 4326).point(-95.99, 28.98))
      post :trippable_autocomplete, params: {term: "600 hospital circle, bay city", format: "json"}
      expect(JSON.parse(response.body).map { |a| a["id"] }).to include(address.id)
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
