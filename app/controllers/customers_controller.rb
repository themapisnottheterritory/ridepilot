class CustomersController < ApplicationController
  load_and_authorize_resource :except=>[:card, :autocomplete, :found, :edit, :create, :show, :update, :delete_photo, :inactivate, :reactivate, :prompt_code, :verify_code, :data_for_trip, :get_eligibilities_mobilities_for_trip]

  def autocomplete
    customers = Customer.for_provider(current_provider_id).by_term( params['term'].downcase, 10 ).accessible_by(current_ability)
    customers = customers.active if params[:active_only] == 'true'
    render :json => customers.map { |customer| customer.as_autocomplete }
  end

  def data_for_trip
    @customer = Customer.for_provider(current_provider_id).where(id: params[:customer_id]).first
    render :json => @customer ? @customer.trip_related_data : {}
  end

  def get_eligibilities_mobilities_for_trip
    @customer = Customer.for_provider(current_provider_id).where(id: params[:id]).first
    if @customer
      @ridership_mobility_mappings = @customer.ridership_mobilities.group_by{|c|[c.mobility_id, c.ridership_id]}
    else
      @ridership_mobility_mappings = {}
    end
  end

  def found
    if params[:customer_id].blank?
      redirect_to search_customers_path( :term => params[:customer_name] )
    elsif params[:commit].downcase.starts_with? "new trip"
      redirect_to new_trip_path :customer_id=>params[:customer_id]
    else
      redirect_to customer_path params[:customer_id]
    end
  end

  def index
    @active_only = true
    if params[:active_only] == 'true' || params[:active_only] == 'false'
      @active_only = eval params[:active_only]
      session[:active_customers_only] = @active_only
    else
      @active_only = session[:active_customers_only] unless session[:active_customers_only].nil?
    end

    @customers = Customer.for_provider(current_provider_id).accessible_by(current_ability)
    @customers = @customers.by_letter(params[:letter]) if params[:letter].present?

    @customers = @customers.active if @active_only

    respond_to do |format|
      format.html { @customers = @customers.paginate :page => params[:page], :per_page => PER_PAGE }
      format.xml  { render :xml => @customers }
    end
  end

  def search
    @customers = Customer.for_provider(current_provider_id).by_term(params[:term].downcase).
      accessible_by(current_ability).
      paginate(:page => params[:page], :per_page => PER_PAGE)
      
    render :action => :index
  end

  # GET /customers/:id/card: the small summary shown when hovering a
  # customer's name anywhere in RidePilot, so staff can tell riders apart
  # before opening the full record. Fetched only after the pointer rests on a
  # name, and cached by the page; a handful of small queries.
  def card
    @customer = Customer.find_by(id: params[:id])
    return head(:not_found) unless @customer
    return head(:forbidden) unless @customer.authorized_for_provider(current_provider_id)
    @last_trip, @next_trip = CustomerTrips.new(@customer).last_and_next
    render partial: "customers/card", layout: false
  end

  def show
    @customer = Customer.find(params[:id])

    # default scope is pickup time ascending, so reverse
    if !@customer.authorized_for_provider(current_provider_id)
      authorize! :show, @customer 
      raise CanCan::AccessDenied.new("Not authorized!", :show, @customer)
    else
      @read_only_customer = false
      @read_only_customer = true if @customer.provider_id != current_provider.id
    end

    prep_edit(true)

    @trips    = @customer.trips.reorder('pickup_time desc').paginate :page => params[:page], :per_page => PER_PAGE

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @customer }
    end
  end

  def new
    @customer = Customer.new name_options
    @customer.provider = current_provider
    #@customer.address ||= @customer.build_address :provider => current_provider
    prep_edit

    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @customer }
    end
  end

  def edit
    @customer = Customer.find(params[:id])
    if !@customer.authorized_for_provider(current_provider.id)
      authorize! :edit, @customer 
      raise CanCan::AccessDenied.new("Not authorized!", :edit, @customer)
    end
    prep_edit
  end

  def create
    @customer = Customer.new customer_params
    @customer.provider = current_provider
    @customer.activated_date = Date.today
    edit_addresses
    edit_mobilities

    if params[:ignore_dups] != "1"
      #check for duplicates
      #similar-sounding first/last names and (no or matching) middle initial

      first_name = @customer.first_name
      middle_initial = @customer.middle_initial
      last_name = @customer.last_name
      dup_customers = Customer.accessible_by(current_ability).where([
        "(middle_initial = ? or middle_initial = '' or ? = '') and 

        (dmetaphone(last_name) = dmetaphone(?) or
         dmetaphone(last_name) = dmetaphone_alt(?) or 
         dmetaphone_alt(last_name) = dmetaphone(?) or 
         dmetaphone_alt(last_name) = dmetaphone_alt(?)) and

        (dmetaphone_alt(first_name) = dmetaphone_alt(?) or
         dmetaphone_alt(first_name) = dmetaphone(?) or
         dmetaphone(first_name) = dmetaphone(?)  or
         dmetaphone(first_name) = dmetaphone_alt(?)) or
        (email = ? and email !=  '' and email is not null and ? != '')
        ", 
        middle_initial, middle_initial, 
        last_name, last_name, last_name, last_name, 
        first_name, first_name, first_name, first_name,
        @customer.email, @customer.email]).limit(1)

      if dup_customers.size > 0
        dup = dup_customers[0]
        flash.now[:alert] = "There is already a customer with a similar name or the same email address: <a href=\"#{url_for :action=>:show, :id=>dup.id}\">#{dup.name}</a> (dob #{dup.birth_date}).  If this is truly a different customer, check the 'ignore duplicates' box to continue creating this customer.".html_safe
        @dup = true
        prep_edit
        return render :action=>"new"
      end
    end

    providers = []
    if params[:customer][:authorized_provider_ids].present?
      params[:customer][:authorized_provider_ids].each do |authorized_provider_id|
        providers.push(Provider.find(authorized_provider_id)) if authorized_provider_id.present?
      end
    end

    @customer.authorized_providers = (providers << @customer.provider).uniq

    respond_to do |format|
      if @customer.is_all_valid?(current_provider_id) && @customer.save
        TrackerActionLog.customer_comments_created(@customer, current_user) unless @customer.comments.blank?
        edit_donations
        edit_travel_trainings
        edit_funding_authorization_numbers
        edit_eligibilities
        edit_ada_questions
        format.html { redirect_to(@customer, :notice => 'Customer was successfully created.') }
        format.xml  { render :xml => @customer, :status => :created, :location => @customer }
      else
        prep_edit
        format.html { render :action => "new" }
        format.xml  { render :xml => @customer.errors, :status => :unprocessable_entity }
      end
    end
  end

  def inactivate
    @customer = Customer.find_by_id(params[:id])

    authorize! :update, @customer
    
    prev_active_text = @customer.active_status_text
    prev_reason = @customer.active_status_changed_reason

    @customer.assign_attributes customer_inactivate_params

    if @customer.inactivated?
      if @customer.permanent_inactivated?
        @customer.inactivated_date = Date.today
        @customer.inactivated_start_date = nil
        @customer.inactivated_end_date = nil
      else
        if @customer.inactivated_end_date.present? && !@customer.inactivated_start_date.present?
          @customer.inactivated_start_date = Date.today.in_time_zone
        end
      end
    else
      @customer.active_status_changed_reason = nil  
    end

    if @customer.changed?
      TrackerActionLog.customer_active_status_changed(@customer, current_user, prev_active_text, prev_reason)
    end

    @customer.save(validate: false)

    redirect_to @customer
  end

  def reactivate
    @customer = Customer.find(params[:id])
    authorize! :edit, @customer

    prev_active_text = @customer.active_status_text
    prev_reason = @customer.active_status_changed_reason

    @customer.reactivate!

    TrackerActionLog.customer_active_status_changed(@customer, current_user, prev_active_text, prev_reason)

    redirect_to @customer
  end

  def update
    @customer = Customer.find(params[:id])

    authorize! :update, @customer if !@customer.authorized_for_provider(current_provider.id)

    customer_attrs = customer_params
    customer_attrs = customer_attrs.except(:photo_attributes) if customer_attrs[:photo_attributes].blank?

    @customer.assign_attributes customer_attrs
    edit_addresses
    edit_mobilities

    #save address changes
    if address_attributes_param && address_attributes_param[:id].present?
      address = Address.find(address_attributes_param[:id])
      address.assign_attributes(address_params)
    end

    providers = []
    if params[:customer][:authorized_provider_ids].present?
      params[:customer][:authorized_provider_ids].each do |authorized_provider_id|
        providers.push(Provider.find(authorized_provider_id)) if authorized_provider_id.present?
      end
    end
    @customer.authorized_providers = (providers << @customer.provider).uniq

    customer_comments_updated = @customer.comments_changed?

    respond_to do |format|
      if @customer.is_all_valid?(current_provider_id) && @customer.save
        TrackerActionLog.customer_comments_updated(@customer, current_user) if customer_comments_updated
        edit_donations
        edit_travel_trainings
        edit_funding_authorization_numbers
        edit_eligibilities
        edit_ada_questions
        format.html { redirect_to(@customer, :notice => 'Customer was successfully updated.') }
        format.xml  { head :ok }
      else
        prep_edit
        format.html { render :action => "edit" }
        format.xml  { render :xml => @customer.errors, :status => :unprocessable_entity }
      end
    end
  end

  def destroy
    if @customer.trips.present?
      if new_customer = @customer.replace_with!(params[:customer_id])
        redirect_to new_customer, :notice => "#{@customer.name} was successfully deleted."
      else
        redirect_to @customer, :notice => "#{@customer.name} can't be deleted without associating trips with another customer."
      end
    else
      @customer.destroy
      redirect_to customers_url, :notice => "#{@customer.name} was successfully deleted."
    end
  end

  def delete_photo
    @customer = Customer.find_by_id(params[:id])

    authorize! :update, @customer if !@customer.authorized_for_provider(current_provider.id)

    @customer.photo.try(:destroy!)

    redirect_to @customer, :notice => "Photo has been deleted."
  end
  
  # Displays a report of customer comments for a given customer
  def customer_comments_report
    @customer = Customer.find(params[:id])
    
    render layout: false
  end

  def prompt_code
    @customer = Customer.find_by_id(params[:id])
    if @customer && !@customer.code.blank? && session["client_code_#{@customer.id}"] != '1'
      show_prompt = true
    end

    render :json => {
      id: @customer.try(:id), 
      code: @customer.try(:code),
      show_prompt: show_prompt
    }
  end

  def verify_code
    @customer = Customer.find_by_id(params[:id])
    if @customer
      session["client_code_#{@customer.id}"] = '1'
    end
  end
  
  private
  
  def customer_params
    params.require(:customer).permit(
      :gender,
      :ada_eligible,
      :ada_ineligible_reason,
      :birth_date,
      :default_funding_source_id,
      :service_level_id,
      :email,
      :emergency_contact_notes,
      :ethnicity,
      :first_name,
      :group,
      :last_name,
      :medicaid_eligible,
      :middle_initial,
      :mobility_id,
      :mobility_notes,
      :phone_number_1,
      :phone_number_2,
      :prime_number,
      :private_notes,
      :public_notes,
      :authorized_provider_ids,
      :is_elderly,
      :default_rider_category_id,
      :message,
      :code,
      :comments,
      :travel_trainings,
      :funding_authorization_numbers,
      :passenger_load_min,
      :passenger_unload_min,
      photo_attributes: [:image],
      :address_attributes => [
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

  def customer_inactivate_params
    params.require(:customer).permit(
      :active,
      :inactivated_start_date,
      :inactivated_end_date,
      :active_status_changed_reason
    )
  end

  def address_attributes_param
    params[:customer][:address_attributes]
  end

  def address_params
    address_attributes_param.permit(
      :name, :building_name, :address, 
      :city, :state, :zip, :in_district, 
      :provider_id, :phone_number, :inactive, 
      :trip_purpose_id, :notes) if address_attributes_param
  end

  def name_options
    if params[:customer_name]
      parts = params[:customer_name].split " "
      atts  = { :first_name => parts.first }

      case parts.length
      when 2
        atts[:last_name]      = parts.last
      else
        atts[:middle_initial] = parts[1]
        atts[:last_name]      = parts[2, parts.length - 2].join " "
      end if parts.length > 1

      atts
    end || {}
  end
  
  def prep_edit(readonly = false)
    @mobilities = Mobility.by_provider(current_provider)
    @ethnicity_names = (Ethnicity.by_provider(current_provider).collect(&:name) + [@customer.ethnicity]).compact.sort.uniq
    @funding_sources = FundingSource.by_provider(current_provider)
    @service_levels = ServiceLevel.by_provider(current_provider).pluck(:name, :id)
    
    unless readonly
      @customer.address ||= @customer.build_address provider: current_provider
      @customer.build_photo unless @customer.photo.present?
    end

    get_donations
  end

  def edit_addresses
    if params[:addresses]
      addresses = JSON.parse(params[:addresses], symbolize_names: true)
      @customer.edit_addresses addresses, params[:mailing_address_index].to_i || 0
    end
  end

  def get_donations
    if params[:donations]
      @donations = JSON.parse(params[:donations], symbolize_names: true).map {|d_obj| 
        if d_obj[:id]
          Donation.where(id: d_obj[:id].to_i).first
        else
          Donation.parse donation_hash, nil, current_user
        end
      }
    else
      @donations = @customer.donations.order('date desc')
    end
  end

  def edit_donations
    if params[:donations]
      donations = JSON.parse(params[:donations], symbolize_names: true)
      @customer.edit_donations donations, current_user
    end
  end
  
  def edit_travel_trainings
    if params[:travel_trainings]
      travel_trainings = JSON.parse(params[:travel_trainings], symbolize_names: true)
      @customer.edit_travel_trainings(travel_trainings)
    end
  end

  def edit_funding_authorization_numbers
    if params[:funding_authorization_numbers]
      funding_numbers = JSON.parse(params[:funding_authorization_numbers], symbolize_names: true)
      @customer.edit_funding_authorization_numbers(funding_numbers)
    end
  end

  def edit_eligibilities
    @customer.edit_eligibilities params[:eligibilities]
  end

  def edit_ada_questions
    @customer.edit_ada_questions params[:ada_questions]
  end

  def edit_mobilities
    unless params[:mobilities].blank?
      mobilities = JSON.parse(params[:mobilities], symbolize_names: true)
      @customer.ridership_mobilities.delete_all

      mobilities.each do |config|
        @customer.ridership_mobilities.build(mobility_id: config[:mobility_id], ridership_id: config[:ridership_id], capacity: config[:capacity].to_i)
      end
    end
  end

end
