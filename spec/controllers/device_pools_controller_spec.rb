require "rails_helper"

RSpec.describe DevicePoolsController, type: :controller do
  login_admin_as_current_user

  before(:each) do
    @current_user.current_provider.update_attribute(:dispatch, true)
  end

  # This should return the minimal set of attributes required to create a valid
  # DevicePool. As you add validations to DevicePool, be sure to
  # adjust the attributes here as well.
  let(:valid_attributes) {
    attributes_for(:device_pool)
  }

  let(:invalid_attributes) {
    attributes_for(:device_pool, :name => "", :color => "")
  }

  describe "GET #new" do
    it "assigns a new device_pool as @device_pool" do
      get :new, params: {}
      expect(assigns(:device_pool)).to be_a_new(DevicePool)
    end
  end

  describe "GET #edit" do
    it "assigns the requested device_pool as @device_pool" do
      device_pool = create(:device_pool, :provider => @current_user.current_provider)
      get :edit, params: {:id => device_pool.to_param}
      expect(assigns(:device_pool)).to eq(device_pool)
    end
  end

  describe "POST #create" do
    context "with valid params" do
      it "creates a new DevicePool" do
        expect {
          post :create, params: {:device_pool => valid_attributes}
        }.to change(DevicePool, :count).by(1)
      end

      it "assigns a newly created device_pool as @device_pool" do
        post :create, params: {:device_pool => valid_attributes}
        expect(assigns(:device_pool)).to be_a(DevicePool)
        expect(assigns(:device_pool)).to be_persisted
      end

      it "redirects to the current user's provider" do
        post :create, params: {:device_pool => valid_attributes}
        expect(response).to redirect_to(@current_user.current_provider)
      end
    end

    context "with invalid params" do
      it "assigns a newly created but unsaved device_pool as @device_pool" do
        post :create, params: {:device_pool => invalid_attributes}
        expect(assigns(:device_pool)).to be_a_new(DevicePool)
      end

      it "re-renders the 'new' template" do
        post :create, params: {:device_pool => invalid_attributes}
        expect(response).to render_template("new")
      end
    end
  end

  describe "PUT #update" do
    context "with valid params" do
      let(:new_attributes) {
        {
          :name => "Name",
          :color => "Colors",
        }
      }

      it "updates the requested device_pool" do
        device_pool = create(:device_pool, :provider => @current_user.current_provider, :name => "Green")
        expect {
          put :update, params: {:id => device_pool.to_param, :device_pool => new_attributes}
        }.to change { device_pool.reload.name }.from("Green").to("Name")
      end
      
      it "assigns the requested device_pool as @device_pool" do
        device_pool = create(:device_pool, :provider => @current_user.current_provider)
        put :update, params: {:id => device_pool.to_param, :device_pool => valid_attributes}
        expect(assigns(:device_pool)).to eq(device_pool)
      end

      it "redirects to the current user's provider" do
        device_pool = create(:device_pool, :provider => @current_user.current_provider)
        put :update, params: {:id => device_pool.to_param, :device_pool => valid_attributes}
        expect(response).to redirect_to(@current_user.current_provider)
      end
    end

    context "with invalid params" do
      it "assigns the device_pool as @device_pool" do
        device_pool = create(:device_pool, :provider => @current_user.current_provider)
        put :update, params: {:id => device_pool.to_param, :device_pool => invalid_attributes}
        expect(assigns(:device_pool)).to eq(device_pool)
      end

      it "re-renders the 'edit' template" do
        device_pool = create(:device_pool, :provider => @current_user.current_provider)
        put :update, params: {:id => device_pool.to_param, :device_pool => invalid_attributes}
        expect(response).to render_template("edit")
      end
    end
  end

  describe "DELETE #destroy" do
    it "destroys the requested device_pool" do
      device_pool = create(:device_pool, :provider => @current_user.current_provider)
      expect {
        delete :destroy, params: {:id => device_pool.to_param}
      }.to change(DevicePool, :count).by(-1)
    end

    context "when responding to :html request" do
      it "redirects to the current user's provider" do
        device_pool = create(:device_pool, :provider => @current_user.current_provider)
        delete :destroy, params: {:id => device_pool.to_param}
        expect(response).to redirect_to(@current_user.current_provider)
      end
    end
    
    context "when responding to a :js request" do
      it "responds with JS" do
        device_pool = create(:device_pool, :provider => @current_user.current_provider)
        delete :destroy, params: {:id => device_pool.to_param, :format => "js"}
        expect(response.media_type).to eq("text/javascript")
      end

      it "includes the deleted device_pool in the JS response" do
        device_pool = create(:device_pool, :provider => @current_user.current_provider)
        delete :destroy, params: {:id => device_pool.to_param, :format => "js"}
        json = JSON.parse(response.body)
        expect(json["device_pool"]["attr"]).to be_a(Hash)
        expect(json["device_pool"]["attr"]["data-id"]).to be_a(Integer)
        expect(json["device_pool"]["attr"]["data-id"]).to eq(device_pool.id)
      end
    end
  end

end
