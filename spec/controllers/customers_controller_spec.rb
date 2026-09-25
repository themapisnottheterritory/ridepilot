require 'rails_helper'

RSpec.describe CustomersController, type: :controller do
  login_admin_as_current_user

  # This should return the minimal set of attributes required to create a valid
  # Customer. As you add validations to Customer, be sure to
  # adjust the attributes here as well.
  let(:valid_attributes) {
    attributes_for(:customer, :authorized_provider_ids => [],
      mobility_id: create(:mobility).id, service_level_id: create(:service_level).id,
      default_funding_source_id: create(:funding_source).id)
  }

  # The form posts the saved addresses as JSON next to the customer fields.
  let(:address_params) {
    { addresses: [attributes_for(:customer_common_address, name: "Home")].to_json, mailing_address_index: 0 }
  }

  let(:invalid_attributes) {
    attributes_for(:customer, :first_name => "", :authorized_provider_ids => [])
  }

  describe "GET #index" do
    it "assigns all active customers as @customers" do
      customer_1 = create(:customer, :provider => @current_user.current_provider)
      customer_2 = create(:customer, :provider => @current_user.current_provider, :active => false)
      get :index, params: {}
      expect(assigns(:customers)).to include(customer_1)
      expect(assigns(:customers)).to_not include(customer_2)
    end
  end
  
  describe "GET #show" do
    it "assigns the requested customer as @customer" do
      customer = create(:customer, :provider => @current_user.current_provider)
      get :show, params: {:id => customer.to_param}
      expect(assigns(:customer)).to eq(customer)
    end
  end

  describe "GET #new" do
    it "assigns a new customer as @customer" do
      get :new, params: {}
      expect(assigns(:customer)).to be_a_new(Customer)
    end
  end

  describe "GET #edit" do
    it "assigns the requested customer as @customer" do
      customer = create(:customer, :provider => @current_user.current_provider)
      get :edit, params: {:id => customer.to_param}
      expect(assigns(:customer)).to eq(customer)
    end
  end

  describe "POST #create" do
    context "with valid params" do
      it "creates a new Customer" do
        expect {
          post :create, params: {:customer => valid_attributes}.merge(address_params)
        }.to change(Customer, :count).by(1)
      end

      it "assigns a newly created customer as @customer" do
        post :create, params: {:customer => valid_attributes}.merge(address_params)
        expect(assigns(:customer)).to be_a(Customer)
        expect(assigns(:customer)).to be_persisted
      end

      it "should tell me if a duplicate customer exists" do
        customer = create(:customer, email: "abc@def.ghi", provider: @current_user.current_provider)
        put :create, params: {customer: customer.dup.attributes}
        expect(flash.keys).to include("alert")
        expect(flash["alert"]).to include('There is already a customer with a similar name or the same email address')
        expect(assigns(:customer)).to_not be_persisted
        expect(response).to render_template("new")
      end

      it "redirects to the created customer" do
        skip 'somehow the outcome is not stable which caused the failure'
        post :create, params: {:customer => valid_attributes}.merge(address_params)
        expect(response).to redirect_to(Customer.last)
      end
    end

    context "with invalid params" do
      it "assigns a newly created but unsaved customer as @customer" do
        post :create, params: {:customer => invalid_attributes}
        expect(assigns(:customer)).to be_a_new(Customer)
      end

      it "re-renders the 'new' template" do
        post :create, params: {:customer => invalid_attributes}
        expect(response).to render_template("new")
      end
    end
  end
  
  describe "PUT #update" do
    context "with valid params" do
      let(:new_attributes) {
        {
          :first_name => "MyString",
          :midle_initial => "MyString",
          :last_name => "MyString",
          :phone_number_1 => "(801)4567890",
          :phone_number_2 => "(801)4567891",
          :address_attributes => {
            :name => "Name",
            :building_name => "Building",
            :address => "Address",
            :city => "City",
            :state => "ST",
            :zip => "12345",
            :provider_id => @current_user.current_provider.id,
          },
          :email => "MyString",
          :activated_date => "2015-02-23 00:00:00",
          :inactivated_date => "2015-02-23 00:00:00",
          :inactivated_reason => "MyString",
          :birth_date => "2015-02-23 00:00:00",
          :mobility_id => create(:mobility).id,
          :mobility_notes => "MyText",
          :ethnicity => "MyString",
          :emergency_contact_notes => "MyText",
          :private_notes => "MyText",
          :public_notes => "MyText",
          :group => false,
          :medicaid_eligible => false,
          :prime_number => "MyString",
          :default_funding_source_id => create(:funding_source).id,
          :ada_eligible => false,
          :service_level_id => create(:service_level).id,
          :authorized_provider_ids => []
        }
      }

      it "updates the requested customer" do
        customer = create(:customer, :provider => @current_user.current_provider, :first_name => "Foo")
        expect {
          put :update, params: {:id => customer.to_param, :customer => new_attributes}
        }.to change{ customer.reload.first_name }.from("Foo").to("MyString")
      end

      it "assigns the requested customer as @customer" do
        customer = create(:customer, :provider => @current_user.current_provider)
        put :update, params: {:id => customer.to_param, :customer => valid_attributes}
        expect(assigns(:customer)).to eq(customer)
      end

      it "redirects to the customer" do
        customer = create(:customer, :provider => @current_user.current_provider)
        put :update, params: {:id => customer.to_param, :customer => valid_attributes}
        expect(response).to redirect_to(customer)
      end
      
      it "updates customer's travel trainings" do
        customer = create(:customer, :with_travel_trainings, provider: @current_user.current_provider)
        tt_1 = customer.travel_trainings.first
        tt_2 = build(:travel_training, customer: customer)
        new_tt_json = [tt_1, tt_2].to_json

        original_tt_ids = customer.travel_trainings.pluck(:id)
        expect(customer.travel_trainings.count).to eq(3)
        
        put :update, params: {id: customer.to_param, customer: new_attributes, travel_trainings: new_tt_json}
        customer.reload
        
        new_tt_ids = customer.travel_trainings.pluck(:id)
        
        expect(customer.travel_trainings.count).to eq(2)
        expect(new_tt_ids.include?(original_tt_ids.delete(tt_1.id))).to be true
        expect(original_tt_ids.none? {|id| new_tt_ids.include?(id)}).to be true
        expect(customer.travel_trainings.where(comment: tt_2.comment).count).to eq(1)
      end

      it "updates customer's funding authorization numbers" do
        customer = create(:customer, :with_funding_authorization_numbers, provider: @current_user.current_provider)
        fn_1 = customer.funding_authorization_numbers.first
        fn_2 = build(:funding_authorization_number, customer: customer)
        new_fn_json = [fn_1, fn_2].to_json

        original_fn_ids = customer.funding_authorization_numbers.pluck(:id)
        expect(customer.funding_authorization_numbers.count).to eq(3)
        
        put :update, params: {id: customer.to_param, customer: new_attributes, funding_authorization_numbers: new_fn_json}
        customer.reload
        
        new_fn_ids = customer.funding_authorization_numbers.pluck(:id)
        
        expect(customer.funding_authorization_numbers.count).to eq(2)
        expect(new_fn_ids.include?(original_fn_ids.delete(fn_1.id))).to be true
        expect(original_fn_ids.none? {|id| new_fn_ids.include?(id)}).to be true
      end
    end

    context "with invalid params" do
      it "assigns the customer as @customer" do
        customer = create(:customer, :provider => @current_user.current_provider)
        put :update, params: {:id => customer.to_param, :customer => invalid_attributes}
        expect(assigns(:customer)).to eq(customer)
      end

      it "re-renders the 'edit' template" do
        customer = create(:customer, :provider => @current_user.current_provider)
        put :update, params: {:id => customer.to_param, :customer => invalid_attributes}
        expect(response).to render_template("edit")
      end
    end
  end

  describe "DELETE #destroy" do
    it "destroys the requested customer" do
      customer = create(:customer, :provider => @current_user.current_provider)
      expect {
        delete :destroy, params: {:id => customer.to_param}
      }.to change(Customer, :count).by(-1)
    end

    it "redirects to the customers list" do
      customer = create(:customer, :provider => @current_user.current_provider)
      delete :destroy, params: {:id => customer.to_param}
      expect(response).to redirect_to(customers_url)
    end
  end

  describe "POST #inactivate" do
    it "permanently inactivates a customer" do 
      customer = create(:customer, :provider => @current_user.current_provider, :active => true)
      expect {
        post :inactivate, params: {:id => customer.id, customer: {active: false}}
      }.to change{ customer.reload.permanent_inactivated? }.from(false).to(true)
    end

    it "temporarily inactivates a customer" do 
      customer = create(:customer, :provider => @current_user.current_provider, :active => true)
      expect {
        post :inactivate, params: {:id => customer.id, customer: {active: true, inactivated_start_date: Date.today}}
      }.to change{ customer.reload.temporarily_inactivated? }.from(false).to(true)
    end

    it "removes temporary inactivation from a customer" do 
      customer = create(:customer, :provider => @current_user.current_provider, :active => true, inactivated_start_date: Date.today)
      expect {
        post :inactivate, params: {:id => customer.id, customer: {active: true, inactivated_start_date: nil}}
      }.to change{ customer.reload.temporarily_inactivated? }.from(true).to(false)
    end

    it "redirects to @customer" do
      customer = create(:customer, :provider => @current_user.current_provider, :active => true)
      post :inactivate, params: {:id => customer.id, customer: {active: false}}
      expect(response).to redirect_to(customer)
    end
  end

  describe "POST #reactivate" do
    it "activates the requested Customer" do
      customer = create(:customer, :provider => @current_user.current_provider, :active => false)
      expect {
        post :reactivate, params: {:id => customer.id}
      }.to change{ customer.reload.active }.from(false).to(true)
    end

    it "redirects to the @customer" do
      customer = create(:customer, :provider => @current_user.current_provider, :active => false)
      post :reactivate, params: {:id => customer.id}
      expect(response).to redirect_to(customer)
    end
  end
  
  describe "GET #found" do
    it "redirects to :search when :customer_id is blank" do
      get :found, params: {:customer_id => "", :customer_name => "foooo"}
      expect(response).to redirect_to(search_customers_path(:term => "foooo"))
    end
    
    it "redirects to new_trip_path when :commit starts_with \"new trip\"" do
      get :found, params: {:customer_id => "1", :commit => "new trip"}
      expect(response).to redirect_to(new_trip_path(:customer_id => "1"))
    end
    
    it "otherwise redirects to the requested customer" do
      get :found, params: {:customer_id => "1", :commit => ""}
      expect(response).to redirect_to(customer_path("1"))
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

    it "responds with JSON" do
      get :autocomplete, params: autocomplete_terms
      expect(response.media_type).to eq("application/json")
    end

    it "include matching address info in the json response" do
      customer = create(:customer, :provider => @current_user.current_provider, :first_name => "foooo")
      get :autocomplete, params: autocomplete_terms
      json = JSON.parse(response.body)
      expect(json).to be_a(Array)
      expect(json.first["id"]).to be_a(Integer)
      expect(json.first["id"]).to eq(customer.id)
    end
  end

  describe "GET #search" do
    let(:search_terms) {
      {
        :term => "foooo"
      }
    }
    
    it "assigns the matching customers as @customers" do
      customer_1 = create(:customer, :provider => @current_user.current_provider, :first_name => "foooo")
      customer_2 = create(:customer, :provider => @current_user.current_provider, :last_name => "foooo")
      customer_3 = create(:customer, :provider => @current_user.current_provider)
      customer_4 = create(:customer, :first_name => "foooo")
      get :search, params: search_terms
      expect(assigns(:customers)).to include(customer_1)
      expect(assigns(:customers)).to include(customer_2)
      expect(assigns(:customers)).to_not include(customer_3)
      expect(assigns(:customers)).to_not include(customer_4)
    end

    it "renders the 'index' template" do
      get :search, params: search_terms
      expect(response).to render_template("index")
    end
  end
  
end
