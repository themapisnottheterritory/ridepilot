class ProvidersController < ApplicationController
  load_and_authorize_resource except: [:create, :upload_vendor_list, :remove_vendor_list, :delete_role, :change_role]
  before_action :redirect_to_current_provider, only: [:users, :drivers, :general, :vehicles, :customers, :addresses]

  def new
    prep_edit
  end

  def create
    @provider = Provider.new
    authorize! :create, Provider

    new_attrs = provider_params

    is_business_address_blank = check_blank_address("business")
    if is_business_address_blank
      new_attrs = new_attrs.except(:business_address_attributes)
    end
    is_mailing_address_blank = check_blank_address("mailing")
    if is_mailing_address_blank
      new_attrs = new_attrs.except(:mailing_address_attributes)
    end

    @provider.attributes = new_attrs
    @provider.business_address = nil if is_business_address_blank
    @provider.mailing_address = nil if is_mailing_address_blank

    if @provider.save
      if @provider.has_admin?
        redirect_to @provider, notice: 'Provider was successfully created.'
      else
        change_user_current_provider
        redirect_to new_user_provider_users_path(@provider), notice: "Please create an admin user for provider: #{@provider.name}"
      end
    else
      prep_edit
      render action: :new
    end
  end

  def edit
    prep_edit
  end

  def update
    new_attrs = provider_params
    is_business_address_blank = check_blank_address("business")
    if is_business_address_blank
      prev_business_address = @provider.business_address
      @provider.business_address_id = nil
      new_attrs = new_attrs.except(:business_address_attributes)
    end

    is_mailing_address_blank = check_blank_address("mailing")
    if is_mailing_address_blank
      prev_mailing_address = @provider.mailing_address
      @provider.mailing_address_id = nil
      new_attrs = new_attrs.except(:mailing_address_attributes)
    end

    @provider.attributes = new_attrs

    if @provider.save
      prev_business_address.destroy if is_business_address_blank && prev_business_address.present?
      prev_mailing_address.destroy if is_mailing_address_blank && prev_mailing_address.present?
      if @provider.has_admin?
        redirect_to @provider, notice: 'Provider was successfully updated.'
      else
        change_user_current_provider
        redirect_to new_user_provider_users_path(@provider), notice: "Please create an admin user for provider: #{@provider.name}"
      end
    else
      prep_edit
      render action: :edit
    end
  end

  def index
    @providers = @providers.order(:name)
    @providers = @providers.active if params[:show_inactive] != 'true'
  end
  
  def show
    # change current provider
    if @provider.active? && @provider != current_provider && can?(:read, @provider)
      change_user_current_provider
    end

    @readonly = true
    prep_edit
  end

  def save_operating_hours
    errors = create_or_update_hours!
    if errors
      flash[:alert] = 'There is error updating operating hours. Please make sure From Time is earlier than To Time.'
      redirect_back(fallback_location: general_provider_path(@provider, anchor: "hour_settings"))
    else
      redirect_to general_provider_path(@provider, anchor: "hour_settings")
    end
  end

  # POST /providers/:id/save_region
  def save_region
    north = params[:region_north].to_f
    west = params[:region_west].to_f
    south = params[:region_south].to_f
    east = params[:region_east].to_f
    if north == 0.0 and west == 0.0
      @provider.region_nw_corner = nil
    else
      @provider.region_nw_corner = Address.compute_geom(north, west)
    end
    if south == 0.0 and east == 0.0
      @provider.region_se_corner = nil
    else
      @provider.region_se_corner = Address.compute_geom(south, east)
    end
    @provider.save!

    redirect_to general_provider_path(@provider, anchor: "region_map")
  end

  # POST /providers/:id/save_viewport
  def save_viewport
    lat = params[:viewport_lat].to_f
    lng = params[:viewport_lng].to_f
    zoom = params[:viewport_zoom].to_i
    if zoom < 0 or zoom >= 20
      flash.now[:alert] = 'Zoom must be between 0 and 19.'
      redirect_to provider_path(@provider)
    end
    @provider.viewport_zoom = zoom
    if lat == 0.0 and lng == 0.0
      @provider.viewport_center = nil
      @provider.viewport_zoom = nil
    else
      @provider.viewport_center = Address.compute_geom(lat, lng)
    end
    @provider.save!

    redirect_to general_provider_path(@provider, anchor: "viewport")
  end

  def delete_role
    role = Role.find(params[:role_id])
    user = role.user
    authorize! :edit, role
    role.destroy
    if user.roles.size == 0
      user.destroy
    end

    redirect_to users_provider_path(params[:provider_id])
  end

  def change_role
    role = Role.find(params[:role][:id])
    authorize! :edit, role
    role.level = params[:role][:level]
    role.save!

    redirect_to users_provider_path(params[:provider_id])
  end
  
  def change_cab_enabled
    @provider.update_attribute :cab_enabled, params[:cab_enabled]
    
    redirect_to general_provider_path(@provider, anchor: "cab_settings")
  end
  
  def change_scheduling
    @provider.update_attribute :scheduling, params[:scheduling]

    redirect_to general_provider_path(@provider, anchor: "scheduling_settings")
  end

  def change_run_tracking
    @provider.update_attribute :run_tracking, params[:run_tracking]

    redirect_to general_provider_path(@provider, anchor: "run_tracking_settings")
  end

  def change_avl_settings
    @provider.update_columns(
      use_external_avl: params[:use_external_avl] == 'true',
      avl_source: params[:avl_source].to_s.strip.presence || 'opentransit_api',
      opentransit_url: params[:opentransit_url].to_s.strip,
      busavl_host: params[:busavl_host].to_s.strip,
      busavl_database: params[:busavl_database].to_s.strip.presence || 'busavl',
      busavl_username: params[:busavl_username].to_s.strip,
      busavl_password: params[:busavl_password].to_s.strip
    )

    # Start the poller if AVL was just enabled
    if @provider.use_external_avl
      AvlPollerWorker.perform_async
    end

    redirect_to general_provider_path(@provider, anchor: "avl_settings")
  end

  def change_advance_day_scheduling
    @provider.update_attribute :advance_day_scheduling, params[:advance_day_scheduling]
    
    redirect_to general_provider_path(@provider, anchor: "advance_day_settings")
  end

  def change_eligible_age
    @provider.update_attribute :eligible_age, params[:eligible_age]
    
    redirect_to customers_provider_path(@provider)
  end

  def change_reimbursement_rates
    @provider.update reimbursement_params

    redirect_to general_provider_path(@provider, anchor: "reimbursement_rates_settings")
  end
  
  def change_fields_required_for_run_completion

    new_fields = if params[:fields_required_for_run_completion]
      params[:fields_required_for_run_completion].select{ |attr| Run::FIELDS_FOR_COMPLETION.include?(attr.try(:to_sym)) }
    else
      []
    end

    @provider.update_attribute :fields_required_for_run_completion, new_fields

    redirect_to general_provider_path(@provider, anchor: "run_fields_settings")
  end

  def change_driver_availability_settings
    @provider.update(driver_availability_params)

    redirect_to drivers_provider_path(@provider)
  end

  def change_eta_related_settings
    @provider.update(eta_related_params)

    redirect_to general_provider_path(@provider, anchor: "eta_related_settings")
  end

  def change_fare_related_settings
    if @provider.fare
      @provider.fare.update(fare_related_params)
    else
      fare = @provider.build_fare
      fare.update(fare_related_params)
      @provider.save(validate: false)
    end

    redirect_to general_provider_path(@provider, anchor: "fare_related_settings")
  end

  def inactivate
    @provider = Provider.find(params[:id])
    authorize! :edit, @provider

    @provider.inactivate!(params[:provider][:inactivated_reason])
    TrackerActionLog.provider_active_status_changed @provider, current_user

    redirect_to @provider
  end

  def reactivate
    @provider = Provider.find(params[:id])
    authorize! :edit, @provider

    @provider.reactivate!
    TrackerActionLog.provider_active_status_changed @provider, current_user

    redirect_to @provider
  end

  def general
    @hours = @provider.hours_hash

    @start_hours = OperatingHour.available_start_times
    @end_hours = OperatingHour.available_end_times

    array = (0..19).zip(0..19).map()
    @zoom_choices = array.inject({}) do |memo, values|
      memo[values.first.to_s] = values.last.to_s
      memo
    end
  end 

  def users
  end
  
  def drivers
  end

  def vehicles
    @unassigned_drivers = Driver.unassigned(@provider)
    @unassigned_vehicles = Vehicle.unassigned(@provider)
  end

  def addresses
  end

  def customers
  end
  
  def upload_vendor_list
    @provider = Provider.find(params[:id])
    authorize! :manage, Vehicle
    
    if @provider.update_vendor_list(provider_params[:vendor_list])
      flash[:notice] = "Vendor List Uploaded Successfully"
    else
      flash[:alert] = "Vendor List Upload Failed"
    end
    redirect_to vehicles_path
  end
  
  def remove_vendor_list
    @provider = Provider.find(params[:id])
    authorize! :manage, Vehicle
    
    if @provider.remove_vendor_list
      flash[:notice] = "Vendor List Successfully Removed"
    else
      flash[:alert] = "Vendor List Removal Failed"
    end
    
    redirect_to vehicles_path
  end
  
  private
  
  def provider_params
    params.require(:provider).permit(
      :name, :logo, :phone_number, :alt_phone_number, :url, :primary_contact_name, :primary_contact_phone_number,
      :primary_contact_email, :admin_name, :vendor_list,
      :business_address_attributes => [
        :address,
        :building_name,
        :city,
        :name,
        :provider_id,
        :state,
        :zip,
        :notes
      ],
      :mailing_address_attributes => [
        :address,
        :building_name,
        :city,
        :name,
        :provider_id,
        :state,
        :zip,
        :notes
      ]
    )
  end

  def driver_availability_params
    params.require(:provider).permit(
      :driver_availability_min_hour,
      :driver_availability_max_hour,
      :driver_availability_interval_min,
      :driver_availability_days_ahead
      )
  end

  def eta_related_params
    params.require(:provider).permit(
      :passenger_load_min,
      :passenger_unload_min,
      :very_early_arrival_threshold_min,
      :early_arrival_threshold_min,
      :late_arrival_threshold_min,
      :very_late_arrival_threshold_min
      )
  end

  def fare_related_params
    params.require(:fare).permit(
      :fare_type,
      :pre_trip
      )
  end

  def reimbursement_params
    params.permit(*Provider::REIMBURSEMENT_ATTRIBUTES)
  end

  def create_or_update_hours!
    ProviderOperatingHoursProcessor.new(@provider, {
      hours: params[:hours],
      start_hour: params[:start_hour],
      end_hour: params[:end_hour]
      }).process!
  end

  def prep_edit
    @provider.business_address ||= @provider.build_business_address(provider_id: @provider.id)
    @provider.mailing_address ||= @provider.build_mailing_address(provider_id: @provider.id) 
  end

  def check_blank_address(type)
    address_params = provider_params["#{type}_address_attributes".to_sym]
    is_blank = true
    address_params.keys.each do |key|
      next if key.to_s == 'provider_id'
      unless address_params[key].blank?
        is_blank = false
        break
      end
    end if address_params

    is_blank
  end
  
  def redirect_to_current_provider
    if @provider != current_provider
      redirect_to polymorphic_path(current_provider, action: action_name), notice: 'Page reloaded to show data for current selected provider.'
    end
  end

  def change_user_current_provider
    current_user.current_provider = @provider
    current_user.save!

    flash.now[:notice] = "Current provider has been changed to #{@provider.name}"
  end
end
