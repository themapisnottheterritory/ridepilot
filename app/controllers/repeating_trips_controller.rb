class RepeatingTripsController < ApplicationController
  before_action :set_trip, except: [:index, :new, :create, :clone_from_daily_trip]
  authorize_resource :except=>[:show]

  def index
    @trips = RepeatingTrip.active.for_provider(current_provider_id).order(created_at: :desc)
  end

  def new
    @trip = RepeatingTrip.new(:provider_id => current_provider_id)

    prep_view
    
    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @trip }
      format.js   { @remote = true; render :json => {:form => render_to_string(:partial => 'form') }, :content_type => "text/json" }
    end
  end

  def edit
    prep_view
    
    respond_to do |format|
      format.html 
      format.js  { @remote = true; render :json => {:form => render_to_string(:partial => 'form')}, :content_type => "text/json" }
    end
  end
  
  def show
    @trip = RepeatingTrip.find(params[:id])
    prep_view

    authorize! :show, @trip unless @trip.customer && @trip.customer.authorized_for_provider(current_provider.id)
    
    respond_to do |format|
      format.html 
      format.js  { @remote = true; render :json => {:form => render_to_string(:partial => 'form')}, :content_type => "text/json" }
    end
  end

  def create
    params[:repeating_trip][:provider_id] = current_provider_id   
    @trip = RepeatingTrip.new(trip_params)
    process_address
    authorize! :manage, @trip
    edit_mobilities

    respond_to do |format|
      if @trip.is_all_valid?(current_provider_id) && @trip.save
        TrackerActionLog.create_subscription_trip(@trip, current_user)
        format.html {
          if params[:from_dispatch] == 'true'
            redirect_to recurring_dispatchers_path(run_id: params[:run_id]), :notice => 'Subscription trip template was successfully created.'
          else
            redirect_to(@trip, :notice => 'Subscription trip template was successfully created.')
          end
        }
      else
        prep_view
        format.html { render :action => "new" }
      end
    end

  end

  def update
    if params[:repeating_trip][:customer_id] && customer = Customer.find_by_id(params[:repeating_trip][:customer_id])
      authorize! :read, customer
    else
      params[:repeating_trip][:customer_id] = @trip.customer_id
    end    
    process_address
    authorize! :manage, @trip

    prev_schedule = @trip.schedule
    @trip.assign_attributes(trip_params)

    is_run_disrupted = @trip.run_disrupted_by_trip_changes?

    edit_mobilities
    changes = @trip.changes
    respond_to do |format|
      if @trip.is_all_valid?(current_provider_id) && @trip.save
        TrackerActionLog.update_subscription_trip(@trip, current_user, changes, prev_schedule)
        @trip.unschedule! if is_run_disrupted
        format.html { 
          if params[:from_dispatch] == 'true'
            redirect_to recurring_dispatchers_path(run_id: params[:run_id]), :notice => 'Trip was successfully updated.'  
          else
            redirect_to @trip, :notice => 'Trip was successfully updated.'  
          end
        }
      else
        prep_view
        format.html { render :action => "edit"  }
      end
    end
  end

  def destroy
    @trip.unschedule!
    @trip.destroy

    respond_to do |format|
      format.html { redirect_to(repeating_trips_url) }
      format.xml  { head :ok }
      format.js   { render :json => {:status => "success"}, :content_type => "text/json" }
    end
  end

  # use another repeating trip as template
  def clone
    @trip = @trip.clone_for_future!
    prep_view
    
    respond_to do |format|
      format.html { render action: :new }
    end
  end

  # use daily trip as template
  def clone_from_daily_trip
    daily_trip = Trip.find_by_id(params[:trip_id])
    if daily_trip.present?
      @trip = daily_trip.clone_for_repeating_trip!
    else
      @trip = RepeatingTrip.new(:provider_id => current_provider_id)
    end

    prep_view
    
    respond_to do |format|
      format.html { render action: :new }
    end
  end

  def return
    @is_return = true
    @trip = @trip.clone_for_return!

    prep_view

    respond_to do |format|
      format.html { render action: :new }
      format.xml  { render :xml => @trip }
      format.js   { @remote = true; render :json => {:form => render_to_string(:partial => 'form') }, :content_type => "text/json" }
    end
  end

  private

  def set_trip
    @trip = RepeatingTrip.find_by_id(params[:id])
  end
  
  def trip_params
    params.require(:repeating_trip).permit(
      :appointment_time,
      :customer_id,
      :dropoff_address_id,
      :dropoff_address_notes,
      :funding_source_id,
      :medicaid_eligible,
      :mobility_id,
      :notes,
      :pickup_address_id,
      :pickup_address_notes,
      :pickup_time,
      :provider_id, # We normally wouldn't accept this and would set it manually on the instance, but in this controller we're setting it in the params dynamically
      :repeats_sundays,
      :repeats_mondays,
      :repeats_tuesdays,
      :repeats_wednesdays,
      :repeats_thursdays,
      :repeats_fridays,
      :repeats_saturdays,
      :repetition_interval,
      :service_level_id,
      :trip_purpose_id,
      :customer_informed,
      :comments,
      :start_date,
      :end_date,
      :passenger_load_min,
      :passenger_unload_min,
      :early_pickup_allowed,
      :direction,
      :linking_trip_id,
      customer_attributes: [:id]
    )
  end

  def prep_view
    @customer           = @trip.customer
    @mobilities         = Mobility.by_provider(current_provider).order(:name)
    @funding_sources    = FundingSource.by_provider(current_provider)
    @trip_purposes      = TripPurpose.by_provider(current_provider).order(:name)
    @drivers            = Driver.active.for_provider @trip.provider_id
    @vehicles           = Vehicle.active.for_provider(@trip.provider_id)
    @vehicles           = add_cab(@vehicles) if current_provider.try(:cab_enabled?)
    
    @repeating_vehicles = @vehicles 
    @service_levels     = ServiceLevel.by_provider(current_provider).order(:name).pluck(:name, :id)
  end

  def add_cab(vehicles)
    cab_vehicle = Vehicle.new :name => "Cab"
    cab_vehicle.id = -1
    [cab_vehicle] + vehicles 
  end

  def process_address
    pickup_addr_data = params[:trip_pickup_address_data].presence || params[:trip_pickup_google_address].presence
    dropoff_addr_data = params[:trip_dropoff_address_data].presence || params[:trip_dropoff_google_address].presence

    if params[:repeating_trip][:pickup_address_id].blank?
      if !pickup_addr_data.blank?
        addr_params = JSON(pickup_addr_data)
        new_temp_addr = TempAddress.new(addr_params.select{|x| TempAddress.allowable_params.include?(x) })
        new_temp_addr.the_geom = Address.compute_geom(addr_params['lat'], addr_params['lon'])
        @trip.pickup_address = new_temp_addr
      elsif !params[:trip_pickup_lat].blank? && !params[:trip_pickup_lon].blank?
        new_temp_addr = GeocodedAddress.new
        new_temp_addr.the_geom = Address.compute_geom(params['trip_pickup_lat'], params['trip_pickup_lon'])
        @trip.pickup_address = new_temp_addr
      end
    end

    if params[:repeating_trip][:dropoff_address_id].blank?
      if !dropoff_addr_data.blank?
        addr_params = JSON(dropoff_addr_data)
        new_temp_addr = TempAddress.new(addr_params.select{|x| TempAddress.allowable_params.include?(x)})
        new_temp_addr.the_geom = Address.compute_geom(addr_params['lat'], addr_params['lon'])
        @trip.dropoff_address = new_temp_addr
      elsif !params[:trip_dropoff_lat].blank? && !params[:trip_dropoff_lon].blank?
        new_temp_addr = GeocodedAddress.new
        new_temp_addr.the_geom = Address.compute_geom(params['trip_dropoff_lat'], params['trip_dropoff_lon'])
        @trip.dropoff_address = new_temp_addr
      end
    end
  end

  def edit_mobilities
    unless params[:mobilities].blank?
      mobilities = JSON.parse(params[:mobilities], symbolize_names: true)
      @trip.ridership_mobilities.delete_all

      sum_by_ridership = {}
      mobilities.each do |config|
        ridership_id = config[:ridership_id].to_i
        capacity = config[:capacity].to_i
        sum_by_ridership[ridership_id] = 0 if !sum_by_ridership.has_key?(ridership_id)
        sum_by_ridership[ridership_id] += capacity
        @trip.ridership_mobilities.build(mobility_id: config[:mobility_id], ridership_id: ridership_id, capacity: capacity)
      end

      # update space totals
      @trip.customer_space_count = sum_by_ridership[1].to_i
      @trip.guest_count = sum_by_ridership[2].to_i
      @trip.attendant_count = sum_by_ridership[3].to_i
      @trip.service_animal_space_count = sum_by_ridership[4].to_i
    end
  end
end