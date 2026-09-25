require "rails_helper"

RSpec.describe DevicePoolDriversController, type: :controller do
  login_admin_as_current_user
  
  before(:each) do
    @current_user.current_provider.update_attribute(:dispatch, true)
    @device_pool = create(:device_pool, :provider => @current_user.current_provider)
    @driver = create(:driver, :provider => @current_user.current_provider, :user => create(:user, :current_provider => @current_user.current_provider))
  end
  
  # This should return the minimal set of attributes required to create a valid
  # DevicePoolDriver. As you add validations to DevicePoolDriver, be sure to
  # adjust the attributes here as well.
  let(:valid_attributes) {
    # Nothing is required, must have either a driver_id or a vehicle_id
    attributes_for(:device_pool_driver, :driver_id => @driver.id)
  }

  let(:invalid_attributes) {
    attributes_for(:device_pool_driver, :driver_id => "", :vehicle_id => "")
  }

  describe "POST #create" do
    render_views
    
    context "with valid params" do
      it "creates a new DevicePoolDriver" do
        expect {
          post :create, params: {:device_pool_id => @device_pool.id, :device_pool_driver => valid_attributes}
        }.to change(DevicePoolDriver, :count).by(1)
      end

      it "assigns a newly created device_pool_driver as @device_pool_driver" do
        post :create, params: {:device_pool_id => @device_pool.id, :device_pool_driver => valid_attributes}
        expect(assigns(:device_pool_driver)).to be_a(DevicePoolDriver)
        expect(assigns(:device_pool_driver)).to be_persisted
      end

      it "responds with JSON" do
        post :create, params: {:device_pool_id => @device_pool.id, :device_pool_driver => valid_attributes}
        expect(response.media_type).to eq("application/json")
      end

      it "renders a row including the new device_pool_driver attributes in the json response" do
        post :create, params: {:device_pool_id => @device_pool.id, :device_pool_driver => valid_attributes}
        json = JSON.parse(response.body)
        expect(json["row"]).to be_a(String)
        expect(json["row"]).to include(device_pool_device_pool_driver_path(@device_pool, DevicePoolDriver.last))
      end
    end

    context "with invalid params" do
      it "assigns a newly created but unsaved device_pool_driver as @device_pool_driver" do
        post :create, params: {:device_pool_id => @device_pool.id, :device_pool_driver => invalid_attributes}
        expect(assigns(:device_pool_driver)).to be_a_new(DevicePoolDriver)
      end

      it "responds with JSON" do
        post :create, params: {:device_pool_id => @device_pool.id, :device_pool_driver => invalid_attributes}
        expect(response.media_type).to eq("application/json")
      end

      it "includes validation errors in the json response" do
        post :create, params: {:device_pool_id => @device_pool.id, :device_pool_driver => invalid_attributes}
        json = JSON.parse(response.body)
        expect(json["errors"]).to be_a(Hash)
        expect(json["errors"]["base"].first).to include("must have either an associated driver or an associated vehicle")
      end
    end
  end

  describe "DELETE #destroy" do
    it "destroys the requested device_pool_driver" do
      device_pool_driver = create(:device_pool_driver, :device_pool => @device_pool)
      expect {
        delete :destroy, params: {:device_pool_id => @device_pool.id, :id => device_pool_driver.to_param}
      }.to change(DevicePoolDriver, :count).by(-1)
    end

    it "responds with JSON" do
      device_pool_driver = create(:device_pool_driver, :device_pool => @device_pool)
      delete :destroy, params: {:device_pool_id => @device_pool.id, :id => device_pool_driver.to_param}
      expect(response.media_type).to eq("application/json")
    end

    it "include the deleted device_pool_driver in the json response" do
      device_pool_driver = create(:device_pool_driver, :device_pool => @device_pool)
      delete :destroy, params: {:device_pool_id => @device_pool.id, :id => device_pool_driver.to_param}
      json = JSON.parse(response.body)
      expect(json["device_pool_driver"]).to be_a(Hash)
      expect(json["device_pool_driver"]["id"]).to be_a(Integer)
      expect(json["device_pool_driver"]["id"]).to eq(device_pool_driver.id)
    end
  end

end
