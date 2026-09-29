require "rails_helper"

RSpec.describe TripsController, type: :controller do
  login_admin_as_current_user

  # This should return the minimal set of attributes required to create a valid
  # Trip. As you add validations to Trip, be sure to
  # adjust the attributes here as well.
  let(:valid_attributes) {
    attributes_for(:trip,
      :customer_id => create(:customer, :provider => @current_user.current_provider).id,
      :pickup_address_id => create(:address, :provider => @current_user.current_provider).id,
      :dropoff_address_id => create(:address, :provider => @current_user.current_provider).id,
      :trip_purpose_id => create(:trip_purpose).id
    )
  }

  let(:invalid_attributes) {
    attributes_for(:trip, 
      :customer_id => create(:customer, :provider => @current_user.current_provider).id,
      :trip_purpose_id => nil
    )
  }

  describe "GET #index" do
    
    context "when responding to a :json request" do
      it "responds with JSON" do
        get :index, params: {:format => "json"}
        expect(response.media_type).to eq("application/json")
      end

      it "assigns trips for the current day as @trips" do
        current_day = Time.now.in_time_zone
        trip_1 = create(:trip, :provider => @current_user.current_provider, :pickup_time => current_day)
        trip_2 = create(:trip, :provider => @current_user.current_provider, :pickup_time => current_day + 1.day)
        get :index, params: {:format => "json"}
        expect(assigns(:trips)).to include(trip_1)
        expect(assigns(:trips)).to_not include(trip_2)
      end
      
      context "when specifying a start param" do
        it "assigns trips for the requested week as @trips" do
          trip_1 = create(:trip, :provider => @current_user.current_provider, :pickup_time => Time.now.in_time_zone)
          trip_2 = create(:trip, :provider => @current_user.current_provider, :pickup_time => 1.week.from_now.in_time_zone)
          get :index, params: {
            trip_filters: {
            :start => 1.week.from_now.in_time_zone.at_beginning_of_week.to_i, 
            :end => 1.week.from_now.in_time_zone.at_end_of_week.to_i
            }, format: :json}
          expect(assigns(:trips)).to_not include(trip_1)
          expect(assigns(:trips)).to include(trip_2)
        end
      end
    end
  end

  describe "GET #customer_trip_summary" do
    it "returns empty when no customer_id is given" do 
      get :customer_trip_summary, params: {:format => "json"}
      expect(assigns(:trips)).to be_empty
    end

    context "when customer_id is given" do
      let(:customer_id) { create(:customer, :provider => @current_user.current_provider).id }
      before do
        # Time.now is now 
        Timecop.freeze(Date.new(2017, 8 ,1))

        pickup_time = DateTime.current.beginning_of_day
        appointment_time = pickup_time + 1.hour

        # today trip
        @today_trip = create(:trip, customer_id: customer_id, pickup_time: pickup_time, appointment_time: appointment_time)

        # past trips
        (1..7).each do |i|
          create(:trip, customer_id: customer_id, pickup_time: pickup_time - i.day, appointment_time: appointment_time - i.day)
        end

        # future trips
        (1..7).each do |i|
          create(:trip, customer_id: customer_id, pickup_time: pickup_time + i.day, appointment_time: appointment_time + i.day)
        end
        
      end

      after do
        Timecop.return
      end

      context "when by default" do
        before do 
          get :customer_trip_summary, params: {:format => "json", :customer_id => customer_id}
        end

        it "returns past trips" do 
          expect(assigns(:trips).minimum(:pickup_time)).to be <= DateTime.current
        end
        it "returns at most 10 trips" do 
          expect(assigns(:trips).count).to be < 10
        end
      end

      context "when show past 5 trips" do
        before do 
          get :customer_trip_summary, params: {:format => "json", :customer_id => customer_id, :past_trips => 5}
        end

        it "returns past trips" do 
          expect(assigns(:trips).minimum(:pickup_time)).to be <= DateTime.current
        end
        it "returns at most 5 trips" do 
          expect(assigns(:trips).count).to be <= 5
        end
      end

      context "when show future 5 trips" do
        before do 
          get :customer_trip_summary, params: {:format => "json", :customer_id => customer_id, :future_trips => 5}
        end

        it "returns past trips" do 
          expect(assigns(:trips).minimum(:pickup_time)).to be >= DateTime.current
        end
        it "returns at most 5 trips" do 
          expect(assigns(:trips).count).to be <= 5
        end
      end

      context "when date range params are given" do
        context "start date is given but not end date" do 
          before do 
            get :customer_trip_summary, params: {:format => "json", :customer_id => customer_id, :start_date => Date.tomorrow} 
          end

          it "returns correct trips" do
            expect(assigns(:trips).minimum(:pickup_time)).to be >= Date.tomorrow
          end
        end
        context "end date is given but not start date" do 
          before do 
            get :customer_trip_summary, params: {:format => "json", :customer_id => customer_id, :end_date => Date.today} 
          end

          it "returns correct trips" do
            expect(assigns(:trips).maximum(:pickup_time)).to be < Date.tomorrow
          end

        end
        context "both start and end dates are given" do 
          before do 
            get :customer_trip_summary, params: {:format => "json", :customer_id => customer_id, :start_date => Date.today, :end_date => Date.today} 
          end

          it "returns correct trips" do
            expect(assigns(:trips)).to match([@today_trip])
          end
        end
      end
    end
  end  

  describe "GET #new" do
    it "assigns a new trip as @trip" do
      get :new, params: {}
      expect(assigns(:trip)).to be_a_new(Trip)
    end
    
    context "when responding to :html request" do
      it "renders the 'new' template" do
        get :new, params: {}
        expect(response).to render_template("new")
      end
    end
    
    context "when responding to a :js request" do
      it "responds with JSON" do
        get :new, params: {:format => "js"}
        expect(response.media_type).to eq("text/json")
      end
      
      context "with rendered views" do
        render_views
        
        skip "responds with the 'new' form partial in the JS response" do
          get :new, params: {:format => "js"}
          json = JSON.parse(response.body)
          expect(json["form"]).to be_a(String)
          expect(json["form"]).to include("action=\"#{trips_path}\"")
        end
      end
    end
  end

  describe "GET #edit" do
    it "assigns the requested trip as @trip" do
      trip = create(:trip, :provider => @current_user.current_provider)
      get :edit, params: {:id => trip.to_param}
      expect(assigns(:trip)).to eq(trip)
    end
    
    context "when responding to :html request" do
      it "renders the 'edit' template" do
        trip = create(:trip, :provider => @current_user.current_provider)
        get :edit, params: {:id => trip.to_param}
        expect(response).to render_template("edit")
      end
    end
    
    context "when responding to a :js request" do
      it "responds with JSON" do
        trip = create(:trip, :provider => @current_user.current_provider)
        get :edit, params: {:id => trip.to_param, :format => "js"}
        expect(response.media_type).to eq("text/json")
      end
      
      context "with rendered views" do
        render_views
        
        it "responds with the 'edit' form partial in the JS response" do
          trip = create(:trip, :provider => @current_user.current_provider)
          get :edit, params: {:id => trip.to_param, :format => "js"}
          json = JSON.parse(response.body)
          expect(json["form"]).to be_a(String)
          expect(json["form"]).to include("action=\"#{trip_path(trip)}\"")
        end
      end
    end
  end

  describe "POST #create" do
    context "with valid params" do
      it "creates a new Trip" do
        expect {
          post :create, params: {:trip => valid_attributes}
        }.to change(Trip, :count).by(1)
      end

      it "assigns a newly created trip as @trip" do
        post :create, params: {:trip => valid_attributes}
        expect(assigns(:trip)).to be_a(Trip)
        expect(assigns(:trip)).to be_persisted
      end
    end

    context "with invalid params" do
      it "assigns a newly created but unsaved trip as @trip" do
        post :create, params: {:trip => invalid_attributes}
        expect(assigns(:trip)).to be_a_new(Trip)
      end

      context "when responding to :html request" do
        it "re-renders the 'new' template" do
          post :create, params: {:trip => invalid_attributes}
          expect(response).to render_template("new")
        end
      end
    end
  end

  describe "PUT #update" do
    context "with valid params" do
      let(:new_attributes) {
        {
          :run_id => create(:run, :provider => @current_user.current_provider).id,
          :customer_id => create(:customer, :provider => @current_user.current_provider).id,
          :pickup_time => "2015-02-25 09:00",
          :appointment_time => "2015-02-25 09:30",
          :pickup_address_id => create(:address, :provider => @current_user.current_provider).id,
          :dropoff_address_id => create(:address, :provider => @current_user.current_provider).id,
          :mobility_id => create(:mobility),
          :funding_source_id => create(:funding_source).id,
          :trip_purpose_id => create(:trip_purpose, name: 'New purpose').id,
          :trip_result_id => create(:trip_result).id,
          :notes => "MyText",
          :customer_informed => false,
          :cab => false,
          :cab_notified => false,
          :guests => "MyText",
          :medicaid_eligible => false,
          :mileage => 1,
          :service_level_id => create(:service_level),
        }
      }

      it "updates the requested trip" do
        trip = create(:trip, :provider => @current_user.current_provider, :trip_purpose => create(:trip_purpose, name: 'Something'))
        expect {
          put :update, params: {:id => trip.to_param, :trip => new_attributes}
        }.to change{ trip.reload.trip_purpose.name }.from("Something").to("New purpose")
      end

      it "assigns the requested trip as @trip" do
        trip = create(:trip, :provider => @current_user.current_provider)
        put :update, params: {:id => trip.to_param, :trip => valid_attributes}
        expect(assigns(:trip)).to eq(trip)
      end

      context "when responding to :html request" do
        it "redirects to the trips list" do
          trip = create(:trip, :provider => @current_user.current_provider)
          put :update, params: {:id => trip.to_param, :trip => valid_attributes}
          expect(response).to redirect_to(trip_url(trip))
        end
      end

      context "when responding to a :js request" do
        it "responds with JSON" do
          trip = create(:trip, :provider => @current_user.current_provider)
          put :update, params: {:id => trip.to_param, :trip => valid_attributes, :format => "js"}
          expect(response.media_type).to eq("text/json")
        end

        it "includes a successful status in the JS response" do
          trip = create(:trip, :provider => @current_user.current_provider)
          put :update, params: {:id => trip.to_param, :trip => valid_attributes, :format => "js"}
          json = JSON.parse(response.body)
          expect(json["status"]).to be_a(String)
          expect(json["status"]).to eq("success")
        end
      end
    end

    context "with invalid params" do
      it "assigns the trip as @trip" do
        trip = create(:trip, :provider => @current_user.current_provider)
        put :update, params: {:id => trip.to_param, :trip => invalid_attributes}
        expect(assigns(:trip)).to eq(trip)
      end

      context "when responding to :html request" do
        it "re-renders the 'edit' template" do
          trip = create(:trip, :provider => @current_user.current_provider)
          put :update, params: {:id => trip.to_param, :trip => invalid_attributes}
          expect(response).to render_template("edit")
        end
      end

      context "when responding to a :js request" do
        it "responds with JSON" do
          trip = create(:trip, :provider => @current_user.current_provider)
          put :update, params: {:id => trip.to_param, :trip => invalid_attributes, :format => "js"}
          expect(response.media_type).to eq("text/json")
        end
        
        it "includes a error status in the JS response" do
          trip = create(:trip, :provider => @current_user.current_provider)
          put :update, params: {:id => trip.to_param, :trip => invalid_attributes, :format => "js"}
          json = JSON.parse(response.body)
          expect(json["status"]).to be_a(String)
          expect(json["status"]).to eq("error")
        end

        context "with rendered views" do
          render_views
          
          it "responds with the 'edit' form partial in the JS response" do
            trip = create(:trip, :provider => @current_user.current_provider)
            put :update, params: {:id => trip.to_param, :trip => invalid_attributes, :format => "js"}
            json = JSON.parse(response.body)
            expect(json["form"]).to be_a(String)
            expect(json["form"]).to include("action=\"#{trip_path(trip)}\"")
          end
        end
      end
    end
  end

  describe "DELETE #destroy" do
    it "destroys the requested trip" do
      trip = create(:trip, :provider => @current_user.current_provider)
      expect {
        delete :destroy, params: {:id => trip.to_param}
      }.to change(Trip, :count).by(-1)
    end

    context "when responding to :html request" do
      it "redirects to the trips list" do
        trip = create(:trip, :provider => @current_user.current_provider)
        delete :destroy, params: {:id => trip.to_param}
        expect(response).to redirect_to(trips_url)
      end
    end

    context "when responding to a :js request" do
      it "responds with JSON" do
        trip = create(:trip, :provider => @current_user.current_provider)
        delete :destroy, params: {:id => trip.to_param, :format => "js"}
        expect(response.media_type).to eq("text/json")
      end

      it "includes a successful status in the JS response" do
        trip = create(:trip, :provider => @current_user.current_provider)
        delete :destroy, params: {:id => trip.to_param, :format => "js"}
        json = JSON.parse(response.body)
        expect(json["status"]).to be_a(String)
        expect(json["status"]).to eq("success")
      end
    end
  end

  describe "POST #confirm" do
    it "assigns the requested trip as @trip" do
      trip = create(:trip, :provider => @current_user.current_provider)
      post :confirm, params: {:trip_id => trip.to_param}
      expect(assigns(:trip)).to eq(trip)
    end
    
    it "updates the trip_result of the requested trip to \"COMP\"" do
      create(:trip_result, code:"COMP", name: 'Complete')
      appointment_time = Time.current
      trip = create(:trip, :pickup_time => (appointment_time - 30.minutes), :appointment_time => appointment_time, :provider => @current_user.current_provider)
      expect {
        post :confirm, params: {:trip_id => trip.to_param}
      }.to change{ trip.reload.trip_result.try(:code) }.to("COMP")
    end

    it "redirects to the unscheduled action" do
      trip = create(:trip, :provider => @current_user.current_provider)
      post :confirm, params: {:trip_id => trip.to_param}
      expect(response).to redirect_to(unscheduled_trips_path)
    end
  end
  
  describe "POST #no_show" do
    it "assigns the requested trip as @trip" do
      trip = create(:trip, :provider => @current_user.current_provider)
      post :no_show, params: {:trip_id => trip.to_param}
      expect(assigns(:trip)).to eq(trip)
    end
    
    it "updates the trip_result of the requested trip to \"NS\"" do
      comp_result = create(:trip_result, code:"NS", name: 'No-show')
      trip = create(:trip, :provider => @current_user.current_provider)
      expect {
        post :no_show, params: {:trip_id => trip.to_param}
      }.to change{ trip.reload.trip_result.try(:code) }.to("NS")
    end

    it "redirects to the reconcile_cab action" do
      trip = create(:trip, :provider => @current_user.current_provider)
      post :no_show, params: {:trip_id => trip.to_param}
      expect(response).to redirect_to(reconcile_cab_trips_path)
    end
  end
    
  describe "POST #reached" do
    it "assigns the requested trip as @trip" do
      trip = create(:trip, :provider => @current_user.current_provider)
      post :reached, params: {:trip_id => trip.to_param}
      expect(assigns(:trip)).to eq(trip)
    end
    
    it "mark the user as having been informed that their trip has been approved or turned down" do
      trip = create(:trip, :provider => @current_user.current_provider)
      expect {
        post :reached, params: {:trip_id => trip.to_param}
      }.to change{[
        trip.reload.called_back_by,
        trip.reload.customer_informed
      ]}.to([@current_user, true])
      expect(trip.called_back_at).to be_within(1.minute).of(Time.now)
    end

    it "redirects to the trips_requiring_callback action" do
      trip = create(:trip, :provider => @current_user.current_provider)
      post :reached, params: {:trip_id => trip.to_param}
      expect(response).to redirect_to(trips_requiring_callback_trips_path)
    end
  end
    
  describe "POST #send_to_cab" do
    it "assigns the requested trip as @trip" do
      trip = create(:trip, :provider => @current_user.current_provider)
      post :send_to_cab, params: {:trip_id => trip.to_param}
      expect(assigns(:trip)).to eq(trip)
    end
    
    it "marks the trip as a cab trip and sets the trip_result \"COMP\"" do
      comp_result = create(:trip_result, code:"COMP", name: 'Complete')
      current_time = Time.current
      trip = create(:trip, :pickup_time => (current_time - 30.minutes), :appointment_time => current_time, :provider => @current_user.current_provider)
      expect {
        post :send_to_cab, params: {:trip_id => trip.to_param}
      }.to change{[
        trip.reload.trip_result.try(:code),
        trip.reload.cab,
        trip.reload.cab_notified        
      ]}.to([
        "COMP",
        true,
        false
      ])
    end

    it "redirects to the reconcile_cab action" do
      trip = create(:trip, :provider => @current_user.current_provider)
      post :send_to_cab, params: {:trip_id => trip.to_param}
      expect(response).to redirect_to(reconcile_cab_trips_path)
    end
  end
    
  describe "POST #turndown" do
    it "assigns the requested trip as @trip" do
      trip = create(:trip, :provider => @current_user.current_provider)
      post :turndown, params: {:trip_id => trip.to_param}
      expect(assigns(:trip)).to eq(trip)
    end
    
    it "updates the trip_result of the requested trip to \"TD\"" do
      comp_result = create(:trip_result, code:"TD", name: 'Turned down')
      trip = create(:trip, :provider => @current_user.current_provider)
      expect {
        post :turndown, params: {:trip_id => trip.to_param}
      }.to change{ trip.reload.trip_result.try(:code) }.to("TD")
    end

    it "redirects to the unscheduled action" do
      trip = create(:trip, :provider => @current_user.current_provider)
      post :turndown, params: {:trip_id => trip.to_param}
      expect(response).to redirect_to(unscheduled_trips_path)
    end
  end  

  describe "GET #reconcile_cab" do
    #the cab company has sent a log of all trips in the past [time period]
    #we want to mark some trips as no-shows.  This will be a paginated
    #list of trips
    
    it "assigns complete and no-show cab trips to @trips" do
      td_result = create(:trip_result, code:"TD", name: "Turned down ")
      comp_result = create(:trip_result, code:"COMP", name: 'Complete')
      ns_result = create(:trip_result, code: 'NS', name:"No-show")

      current_time = Time.current
      trip_1 = create(:cab_trip, :provider => @current_user.current_provider, :trip_result => ns_result)
      trip_2 = create(:cab_trip, :provider => @current_user.current_provider, :trip_result => comp_result, :pickup_time => (current_time - 30.minutes), :appointment_time => current_time)
      trip_3 = create(:trip, :provider => @current_user.current_provider, :trip_result => comp_result, :pickup_time => (current_time - 30.minutes), :appointment_time => current_time)
      trip_4 = create(:cab_trip, :provider => @current_user.current_provider, :trip_result => td_result)
      get :reconcile_cab, params: {}
      expect(assigns(:trips)).to include(trip_1)
      expect(assigns(:trips)).to include(trip_2)
      expect(assigns(:trips)).to_not include(trip_3)
      expect(assigns(:trips)).to_not include(trip_4)
    end
  end
  
  describe "GET #trips_requiring_callback" do
    #The trip coordinator has made decisions on whether to confirm or
    #turn down trips.  Now they want to call back the customer to tell
    #them what's happened.  This is a list of all customers who have
    #not been marked as informed, ordered by when they were last
    #called.

    it "assigns future trips for customers that have not yet been informed to @trips" do
      trip_1 = create(:trip, :provider => @current_user.current_provider, :customer_informed => false, :pickup_time => Date.tomorrow.in_time_zone)
      trip_2 = create(:trip, :provider => @current_user.current_provider, :customer_informed => true,  :pickup_time => Date.tomorrow.in_time_zone)
      trip_3 = create(:trip, :provider => @current_user.current_provider, :customer_informed => false, :pickup_time => Date.yesterday.in_time_zone)
      get :trips_requiring_callback, params: {}
      expect(assigns(:trips)).to include(trip_1)
      expect(assigns(:trips)).to_not include(trip_2)
      expect(assigns(:trips)).to_not include(trip_3)
    end
  end
  
  describe "GET #unscheduled" do
    #The trip coordinatior wants to confirm or turn down individual
    #trips.  This is a list of all trips that haven't been decided
    #on yet.

    it "assigns future trips without a trip result to @trips" do
      ns_result = create(:trip_result, code:"NS", name: 'No-show')
      trip_1 = create(:trip, :provider => @current_user.current_provider, :trip_result => nil,   :pickup_time => Date.tomorrow.in_time_zone)
      trip_2 = create(:trip, :provider => @current_user.current_provider, :trip_result => ns_result, :pickup_time => Date.tomorrow.in_time_zone)
      trip_3 = create(:trip, :provider => @current_user.current_provider, :trip_result => nil,   :pickup_time => Date.yesterday.in_time_zone)
      get :unscheduled, params: {}
      expect(assigns(:trips)).to include(trip_1)
      expect(assigns(:trips)).to_not include(trip_2)
      expect(assigns(:trips)).to_not include(trip_3)
    end
  end
  
  describe "POST #check_double_booked" do
    
    it "returns a list of possible double-booked trips" do
      trip_1 = create(:trip)
      trip_2 = create(:trip, customer: trip_1.customer)
      trip_3 = create(:trip, customer: trip_1.customer)
      check_double_booked_params = {
        trip: {
          id: trip_1.id,
          customer_id: trip_1.customer_id,
          date: trip_1.date.to_s
        },
        format: :js
      }
      
      post :check_double_booked, params: check_double_booked_params
      trips = JSON.parse(response.body)["trips"]
      expect(trips.count).to eq(2)
      expect(trips.map{|t| t["id"]}.sort).to eq([trip_2.id, trip_3.id].sort)
      expect(trips[0]["pickup_time"]).to be
      expect(trips[0]["pickup_address"]).to be
      expect(trips[0]["appointment_time"]).to be
      expect(trips[0]["dropoff_address"]).to be
      
    end

    # The form sends a blank id for a trip not saved yet; that used to become
    # "id != NULL" and hide every existing trip (2026-09-29, George Vasquez
    # booked three times in six minutes).
    it "warns about the customer's other trips that day when booking a new trip" do
      trip_1 = create(:trip)
      trip_2 = create(:trip, customer: trip_1.customer)
      post :check_double_booked, params: { trip: { id: "", customer_id: trip_1.customer_id, date: trip_1.date.to_s }, format: :js }
      expect(JSON.parse(response.body)["trips"].map { |t| t["id"] }.sort).to eq([trip_1.id, trip_2.id].sort)
    end
    
  end
  
end
