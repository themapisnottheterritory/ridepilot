require "rails_helper"

RSpec.describe ProviderCommonAddressesController, type: :controller do
  login_admin_as_current_user

  # This should return the minimal set of attributes required to create a valid
  # Address. As you add validations to Address, be sure to
  # adjust the attributes here as well.
  let(:test_group) {
    create(:address_group)
  }

  let(:valid_attributes) {
    attributes_for(:provider_common_address).merge({address_group_id: test_group.id})
  }

  let(:invalid_attributes) {
    attributes_for(:provider_common_address, :state => "", :address => '', :city => '')
  }

  describe "GET #edit" do
    it "assigns the requested address as @address" do
      address = create(:provider_common_address, :provider => @current_user.current_provider)
      get :edit, params: {:id => address.to_param}
      expect(assigns(:address)).to eq(address)
    end
  end

  describe "POST #create" do
    let(:valid_create_attributes) {
      # Convert the params to a flat list of params because that's what the
      # controller expects
      prefix = "provider_common_address"
      params = {"prefix" => prefix, "#{prefix}" => {}, format: :json}
      valid_attributes.each do |k,v|
        params["#{prefix}"]["#{k}"] = v
      end
      params
    }
  
    context "with valid params" do
      context "specifying an existing address" do
        it "does not create a new Address" do
          address = create(:provider_common_address, :provider => @current_user.current_provider)
          
          expect {
            post :create, params: valid_create_attributes.merge({:address_id => address.id})
          }.to_not change(ProviderCommonAddress, :count)
        end

        it "updates the requested vehicle" do
          address = create(:provider_common_address, :provider => @current_user.current_provider, :address => "Foobar")
          valid_create_attributes["provider_common_address"]["address"] = "Barfoo"
          expect {
            post :create, params: valid_create_attributes.merge({:address_id => address.id})
          }.to change { address.reload.address }.from("Foobar").to("Barfoo")
        end

        it "responds with JSON" do
          address = create(:provider_common_address, :provider => @current_user.current_provider)
          post :create, params: valid_create_attributes.merge({:address_id => address.id})
          expect(response.media_type).to eq("application/json")
        end

        it "includes the address attributes in the json response" do
          address = create(:provider_common_address, :provider => @current_user.current_provider)
          post :create, params: valid_create_attributes.merge({:address_id => address.id})
          json = JSON.parse(response.body)
          expect(json["id"]).to be_a(Integer)
          expect(json["id"]).to eq(address.id)
        end
      end 
    
      context "without specifying an existing new address" do
        it "creates a new Address" do
          expect {
            post :create, params: valid_create_attributes
          }.to change(ProviderCommonAddress, :count).by(1)
        end

        it "responds with JSON" do
          post :create, params: valid_create_attributes
          expect(response.media_type).to eq("application/json")
        end

        it "includes the address attributes in the json response" do
          post :create, params: valid_create_attributes
          json = JSON.parse(response.body)
          expect(json["id"]).to be_a(Integer)
          expect(json["id"]).to eq(ProviderCommonAddress.last.id)
        end

        it "includes the address type in the json response" do
          post :create, params: valid_create_attributes
          json = JSON.parse(response.body)
          expect(json["prefix"]).to eq("provider_common_address")
        end
      end
    end

    context "with invalid params" do
      let(:invalid_create_attributes) {
        valid_create_attributes["provider_common_address"]["address"] = ""
        valid_create_attributes["provider_common_address"]["city"] = ""
        valid_create_attributes["provider_common_address"]["state"] = ""
        valid_create_attributes["provider_common_address"]["zip"] = ""

        valid_create_attributes
      }

      it "responds with JSON" do
        post :create, params: invalid_create_attributes
        expect(response.media_type).to eq("application/json")
      end

      it "includes validation errors in the json response" do
        # Messages come from the translation tables, which the test database
        # does not seed; put the one this example reads in place.
        locale = Locale.find_or_create_by!(name: "en")
        key = TranslationKey.find_or_create_by!(name: "address_required")
        Translation.find_or_create_by!(locale: locale, translation_key: key) { |t| t.value = "Please type address in the Address fields" }
        post :create, params: invalid_create_attributes
        json = JSON.parse(response.body)
        expect(json["base"].first).to include("Please type address in the Address fields")
      end

      it "includes the address type in the json response" do
        post :create, params: invalid_create_attributes
        json = JSON.parse(response.body)
        expect(json["prefix"]).to eq("provider_common_address")
      end
    end
  end

  describe "PUT #update" do
    context "with valid params" do
      let(:new_attributes) {
        {
          :name => "Name",
          :building_name => "Building",
          :address => "Address",
          :city => "City",
          :state => "ST",
          :zip => "12345",
          :in_district => false,
          :the_geom => "",
          :phone_number => "(801)4567890",
          :inactive => false,
          :trip_purpose => create(:trip_purpose, name: "Purpose") ,
          :address_group => test_group
        }
      }

      it "updates the requested address" do
        address = ProviderCommonAddress.create! valid_attributes.merge({:provider_id => @current_user.current_provider.id, :address => "Foobar"})
        expect {
          put :update, params: {:id => address.to_param, :provider_common_address => new_attributes}
        }.to change { address.reload.address }.from("Foobar").to("Address")
      end

      it "assigns the requested address as @address" do
        address = ProviderCommonAddress.create! valid_attributes.merge({:provider_id => @current_user.current_provider.id})
        put :update, params: {:id => address.to_param, :provider_common_address => valid_attributes}
        expect(assigns(:address)).to eq(address)
      end

      it "redirects to the provider of the address" do
        address = ProviderCommonAddress.create! valid_attributes.merge({:provider_id => @current_user.current_provider.id})
        put :update, params: {:id => address.to_param, :provider_common_address => valid_attributes}
        expect(response).to redirect_to(addresses_provider_path(address.provider))
      end
    end

    context "street edits and the pin" do
      let(:pinned) {
        ProviderCommonAddress.create! valid_attributes.merge(provider_id: @current_user.current_provider.id,
          address: "100 Main St", the_geom: Address.compute_geom(28.8, -97.0))
      }

      it "keeps the pin when only the name changes and the form re-sends the current lat/lon" do
        put :update, params: {id: pinned.to_param, lat: 28.8, lon: -97.0,
          provider_common_address: {name: "Renamed", address_group_id: test_group.id}}
        expect(pinned.reload.the_geom).to_not be_nil
        expect(pinned.name).to eq("Renamed")
      end

      it "keeps the pin when a unit number is appended and the current lat/lon comes back" do
        put :update, params: {id: pinned.to_param, lat: 28.8, lon: -97.0,
          provider_common_address: {address: "100 Main St Apt 5", address_group_id: test_group.id}}
        expect(pinned.reload.address).to eq("100 Main St Apt 5")
        expect(pinned.the_geom).to_not be_nil
      end

      it "drops the pin when the street changes and no new lat/lon is sent" do
        put :update, params: {id: pinned.to_param,
          provider_common_address: {address: "200 Other Rd", address_group_id: test_group.id}}
        expect(pinned.reload.address).to eq("200 Other Rd")
        expect(pinned.the_geom).to be_nil
      end

      it "takes the new pin when the street changes with a new lat/lon" do
        put :update, params: {id: pinned.to_param, lat: 29.1, lon: -97.2,
          provider_common_address: {address: "200 Other Rd", address_group_id: test_group.id}}
        expect(pinned.reload.latitude).to be_within(0.0001).of(29.1)
      end
    end

    context "with invalid params" do
      it "assigns the address as @address" do
        address = ProviderCommonAddress.create! valid_attributes.merge({:provider_id => @current_user.current_provider.id})
        put :update, params: {:id => address.to_param, :provider_common_address => invalid_attributes}
        expect(assigns(:address)).to eq(address)
      end

      it "re-renders the 'edit' template" do
        address = ProviderCommonAddress.create! valid_attributes.merge({:provider_id => @current_user.current_provider.id})
        put :update, params: {:id => address.to_param, :provider_common_address => invalid_attributes}
        expect(response).to render_template("edit")
      end
    end
  end

  describe "DELETE #destroy" do
    context "when the address has trips associated with it" do
      before(:each) do
        @address = create(:provider_common_address, :provider => @current_user.current_provider)
        @trip = create(:trip, :provider => @current_user.current_provider, :pickup_address => @address)
      end
    
      context "when a replacement address has been specified" do
        before(:each) do
          @replacement_address = ProviderCommonAddress.create! valid_attributes.merge({:provider_id => @current_user.current_provider.id})
        end
        
        it "destroys the requested address" do
          expect {
            delete :destroy, params: {:id => @address.to_param, :address_id => @replacement_address.id}
          }.to change(ProviderCommonAddress, :count).by(-1)
        end

        it "associates the trips with the replacement address" do
          expect {
            delete :destroy, params: {:id => @address.to_param, :address_id => @replacement_address.id}
          }.to change{ @trip.reload.pickup_address_id }.from(@address.id).to(@replacement_address.id)
        end

        it "redirects to the provider of the replacement address" do
          address = ProviderCommonAddress.create! valid_attributes.merge({:provider_id => @current_user.current_provider.id})
          delete :destroy, params: {:id => address.to_param, :address_id => @replacement_address.id}
          expect(response).to redirect_to( addresses_provider_path(@replacement_address.provider))
        end        
      end
      
      context "when no replacement address has been specified" do
        it "does not destroy the requested address" do
          expect {
            delete :destroy, params: {:id => @address.to_param}
          }.to_not change(ProviderCommonAddress, :count)
        end

        it "redirects to the edit address page" do
          delete :destroy, params: {:id => @address.to_param}
          expect(response).to redirect_to(edit_provider_common_address_path(@address))
        end        
      end
    end
    
    context "when no trips are associated with the address" do
      it "destroys the requested address" do
        address = ProviderCommonAddress.create! valid_attributes.merge({:provider_id => @current_user.current_provider.id})
        expect {
          delete :destroy, params: {:id => address.to_param}
        }.to change(ProviderCommonAddress, :count).by(-1)
      end

      it "redirects to the current user's provider" do
        address = ProviderCommonAddress.create! valid_attributes.merge({:provider_id => @current_user.current_provider.id})
        delete :destroy, params: {:id => address.to_param}
        expect(response).to redirect_to(addresses_provider_path(@current_user.current_provider))
      end
    end
  end

  describe "GET #autocomplete" do
    # Sticking to high-level testing of this action since there's otherwise a 
    # lot of setup involved.
    
    let(:autocomplete_terms) {
      {
        :term => "foooo"
      }
    }

    # MapRequest API now requires a key, current call without key causes HTTP error, so skip for now
    skip "responds with JSON" do
      post :autocomplete, autocomplete_terms
      expect(response.media_type).to eq("application/json")
    end

    it "include matching address info in the json response" do
      address = create(:provider_common_address, :provider => @current_user.current_provider, :name => "foooo")
      post :autocomplete, params: autocomplete_terms
      json = JSON.parse(response.body)
      expect(json).to be_a(Array)
      expect(json.first["id"]).to be_a(Integer)
      expect(json.first["id"]).to eq(address.id)
    end

    # MapRequest API now requires a key, current call without key causes HTTP error, so skip for now
    skip "include a new address in the json response if no other matches are found" do
      post :autocomplete, params: autocomplete_terms
      json = JSON.parse(response.body)
      expect(json).to be_a(Array)
      expect(json.first["id"]).to be_a(Integer)
      expect(json.first["id"]).to eq(0)
    end
  end

  describe "GET #search" do
    let(:search_terms) {
      {
        :name => "foooo",
        :provider_id => @current_user.current_provider.id,
        :format => "json"
      }
    }
    
    it "assigns the search term as @term" do
      get :search, params: search_terms
      expect(assigns(:term)).to eq("foooo")
    end
    
    it "assigns the requested provider as @provider" do
      get :search, params: search_terms
      expect(assigns(:provider)).to eq(@current_user.current_provider)
    end
        
    it "assigns the matching addresses as @addresses" do
      address_1 = create(:provider_common_address, :provider => @current_user.current_provider, :name => "foooo")
      address_2 = create(:provider_common_address, :provider => @current_user.current_provider, :building_name => "foooo")
      address_3 = create(:provider_common_address, :provider => @current_user.current_provider, :address => "foooo")
      address_4 = create(:provider_common_address, :provider => @current_user.current_provider)
      address_5 = create(:provider_common_address)
      get :search, params: search_terms
      expect(assigns(:addresses)).to include(address_1)
      expect(assigns(:addresses)).to include(address_2)
      expect(assigns(:addresses)).to include(address_3)
      expect(assigns(:addresses)).to_not include(address_4)
      expect(assigns(:addresses)).to_not include(address_5)
    end

    it "responds with JSON" do
      get :search, params: search_terms
      expect(response.media_type).to eq("application/json")
    end
  end
end
