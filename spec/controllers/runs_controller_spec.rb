require "rails_helper"

RSpec.describe RunsController, type: :controller do
  login_admin_as_current_user

  # This should return the minimal set of attributes required to create a valid
  # Run. As you add validations to Run, be sure to
  # adjust the attributes here as well.
  before(:each) do
    @driver = create(:driver)
    @vehicle = create(:vehicle)
  end

  let(:valid_attributes) {
    attributes_for(:run, :driver_id => @driver.id, :vehicle_id => @vehicle.id)
  }

  let(:invalid_attributes) {
    attributes_for(:run, :date => "")
  }

  describe "GET #index" do
    it "assigns all runs as @runs" do
      run = create(:run, :provider => @current_user.current_provider)
      get :index, params: {}
      expect(assigns(:runs)).to eq([run])
    end
  end

  describe "GET #new" do
    it "assigns a new run as @run" do
      get :new, params: {}
      expect(assigns(:run)).to be_a_new(Run)
    end
  end

  describe "GET #edit" do
    it "assigns the requested run as @run" do
      run = create(:run, :provider => @current_user.current_provider)
      get :edit, params: {:id => run.to_param}
      expect(assigns(:run)).to eq(run)
    end
  end

  describe "POST #create" do
    context "with valid params" do
      it "creates a new Run" do
        expect {
          post :create, params: {:run => valid_attributes}
        }.to change(Run, :count).by(1)
      end

      it "assigns a newly created run as @run" do
        post :create, params: {:run => valid_attributes}
        expect(assigns(:run)).to be_a(Run)
        expect(assigns(:run)).to be_persisted
      end

      it "redirects to the created run" do
        post :create, params: {:run => valid_attributes}
        expect(response).to redirect_to(run_path(assigns(:run)))
      end
    end

    context "with invalid params" do
      it "assigns a newly created but unsaved run as @run" do
        post :create, params: {:run => invalid_attributes}
        expect(assigns(:run)).to be_a_new(Run)
      end

      it "re-renders the 'new' template" do
        post :create, params: {:run => invalid_attributes}
        expect(response).to render_template("new")
      end
    end
  end

  describe "PUT #update" do
    context "with valid params" do
      let(:new_attributes) {
        {
          :name => "MyString",
          :date => "2015-02-24 00:00:00",
          :start_odometer => 1,
          :end_odometer => 2,
          :scheduled_start_time => "2015-02-24 02:40",
          :scheduled_end_time => "2015-02-24 02:41",
          :unpaid_driver_break_time => 1,
          :vehicle_id => create(:vehicle, :provider => @current_user.current_provider).id,
          :driver_id => create(:driver, :provider => @current_user.current_provider).id,
          :paid => false,
          :complete => false,
          :actual_start_time => "2015-02-24 02:40",
          :actual_end_time => "2015-02-24 02:41",
        }
      }

      it "updates the requested run" do
        run = create(:run, :provider => @current_user.current_provider, :name => "Something")
        expect {
          put :update, params: {:id => run.to_param, :run => new_attributes}
        }.to change{ run.reload.name }.from("Something").to("MyString")
      end

      it "assigns the requested run as @run" do
        run = create(:run, :provider => @current_user.current_provider)
        put :update, params: {:id => run.to_param, :run => valid_attributes}
        expect(assigns(:run)).to eq(run)
      end

      it "redirects to the run" do
        run = create(:run, :provider => @current_user.current_provider)
        put :update, params: {:id => run.to_param, :run => valid_attributes}
        expect(response).to redirect_to(run_path(run))
      end
    end

    context "with invalid params" do
      it "assigns the run as @run" do
        run = create(:run, :provider => @current_user.current_provider)
        put :update, params: {:id => run.to_param, :run => invalid_attributes}
        expect(assigns(:run)).to eq(run)
      end

      it "re-renders the 'edit' template" do
        run = create(:run, :provider => @current_user.current_provider)
        put :update, params: {:id => run.to_param, :run => invalid_attributes}
        expect(response).to render_template("edit")
      end
    end
  end

  describe "DELETE #destroy" do
    it "destroys the requested run" do
      run = create(:run, :provider => @current_user.current_provider)
      expect {
        delete :destroy, params: {:id => run.to_param}
      }.to change(Run, :count).by(-1)
    end

    it "redirects to the runs list" do
      run = create(:run, :provider => @current_user.current_provider)
      delete :destroy, params: {:id => run.to_param}
      expect(response).to redirect_to(runs_path(date_range(run)))
    end
  end
  
  describe "GET #for_date" do
    it "assigns incomplete runs scheduled for the requested date as @runs" do
      run_1 = create(:run, :provider => @current_user.current_provider, :date => Date.today.in_time_zone)
      run_2 = create(:run, :provider => @current_user.current_provider, :date => Date.yesterday.in_time_zone)
      run_3 = create(:run, :provider => @current_user.current_provider, :date => Date.yesterday.in_time_zone)
      run_3.update_attribute(:complete, true)
      get :for_date, params: {:date => Date.yesterday.in_time_zone}
      expect(assigns(:runs)).to_not include(run_1)
      expect(assigns(:runs)).to_not include(run_3)
      expect(assigns(:runs)).to include(run_2)
    end
    
    it "responds with JSON" do
      get :for_date, params: {:date => Date.yesterday.in_time_zone}
      expect(response.media_type).to eq("application/json")
    end

    it "include matching address info in the json response" do
      run = create(:run, :provider => @current_user.current_provider, :date => Date.today.in_time_zone)
      get :for_date, params: {:date => Date.today.in_time_zone}
      json = JSON.parse(response.body)
      expect(json).to be_a(Array)
      expect(json.first["id"]).to be_a(Integer)
      expect(json.first["id"]).to eq(run.id)
    end

    it "include a new cab trip in the json response" do
      get :for_date, params: {:date => Date.today.in_time_zone}
      json = JSON.parse(response.body)
      expect(json).to be_a(Array)
      expect(json.first["id"]).to be_a(Integer)
      expect(json.first["id"]).to eq(-1)
      expect(json.first["label"]).to eq("Cab")
    end
  end
  
  describe "GET #uncompleted_runs" do
    it "assigns incomplete runs as @runs" do
      run_1 = create(:run, :provider => @current_user.current_provider)
      run_1.update_attribute(:complete, true)
      run_2 = create(:run, :provider => @current_user.current_provider)
      get :uncompleted_runs, params: {}
      expect(assigns(:runs)).to_not include(run_1)
      expect(assigns(:runs)).to include(run_2)
    end

    it "renders the 'index' template" do
      get :uncompleted_runs, params: {}
      expect(response).to render_template("index")
    end
  end
  
  describe "PATCH #cancel_multiple, DELETE #delete_multiple" do
    
    let(:run_1) { create(:run) }
    let(:run_2) { create(:run) }
    let(:run_3) { create(:run) }
    let(:trip_1) { create(:trip) }
    let(:trip_2) { create(:trip) }
    let(:trip_3) { create(:trip) }
    before(:each) do
      run_1.trips << trip_1
      run_1.trips << trip_2
      run_2.trips << trip_3
    end
    
    it "can cancel/unschedule multiple runs" do      
      expect(run_1.trips.count).to eq(2)
      expect(run_2.trips.count).to eq(1)
      expect(run_3.trips.count).to eq(0)
      trip_count = Trip.count
      
      patch :cancel_multiple, params: { cancel_multiple_runs: { run_ids: Run.pluck(:id).join(',') } }
    
      expect(run_1.trips.count).to eq(0)
      expect(run_2.trips.count).to eq(0)
      expect(run_3.trips.count).to eq(0)
      expect(Trip.count).to eq(trip_count)
    end
    
    it "can delete multiple runs" do
      trip_count = Trip.count      
      expect(Run.where(id: [run_1.id, run_2.id, run_3.id]).count).to eq(3)
      
      delete :delete_multiple, params: { delete_multiple_runs: { run_ids: Run.pluck(:id).join(',') } }
      
      expect(Run.where(id: [run_1.id, run_2.id, run_3.id]).count).to eq(0)
      expect(Trip.count).to eq(trip_count)
      
    end
    
  end

  private
  
  def date_range(run)
    if run.date
      week_start = run.date.beginning_of_week
      {:start => week_start.to_time.to_i, :end => (week_start + 6.days).to_time.to_i } 
    end    
  end

end
