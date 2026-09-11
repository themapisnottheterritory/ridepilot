class DriversController < ApplicationController
  load_and_authorize_resource except: [:create, :delete_photo, :inactivate, :reactivate, :availability]
  
  # Load documents through their associated parent
  load_and_authorize_resource :document, through: [:driver]

  def index
    @drivers = @drivers.default_order.for_provider(current_provider.id)
    @drivers = @drivers.active if params[:show_inactive] != 'true'
  end

  def show
    prep_edit(readonly: true)
  end

  def new
    @driver.provider = current_provider
    prep_edit
  end

  def edit
    prep_edit
  end

  def update
    new_attrs = driver_params
    is_alt_address_blank = check_blank_alt_address
    if is_alt_address_blank
      prev_alt_address = @driver.alt_address
      @driver.alt_address_id = nil
      new_attrs = new_attrs.except(:alt_address_attributes)
    end

    is_emergency_contact_blank = check_blank_emergency_contact
    is_geocoded_address_blank = check_blank_emergency_contact_geocoded_address
    if is_emergency_contact_blank
      prev_emergency_contact = @driver.emergency_contact
      @driver.emergency_contact = nil
      new_attrs = new_attrs.except(:emergency_contact_attributes)
    elsif is_geocoded_address_blank
      if @driver.emergency_contact
        prev_emergency_contact_address = @driver.emergency_contact.geocoded_address
        @driver.emergency_contact.geocoded_address_id = nil 
      end
      new_attrs[:emergency_contact_attributes] = new_attrs[:emergency_contact_attributes].except(:geocoded_address_attributes)
    end

    new_attrs = new_attrs.except(:photo_attributes) if new_attrs[:photo_attributes].blank?

    @driver.attributes = new_attrs

    if @driver.emergency_contact && @driver.emergency_contact.geocoded_address.present?
      @driver.emergency_contact.geocoded_address.the_geom = Address.compute_geom(params[:lat], params[:lon])
    end
    
    if !@driver.is_all_valid?(current_provider_id)
      prep_edit
      render action: :edit
    else
      begin      
        Driver.transaction do
          @driver.save!
          prev_alt_address.destroy if is_alt_address_blank && prev_alt_address.present?
          prev_emergency_contact.destroy if is_emergency_contact_blank && prev_emergency_contact.present?
          prev_emergency_contact_address.destroy if is_geocoded_address_blank && prev_emergency_contact_address.present?
        end
        redirect_to @driver, notice: 'Driver was successfully updated.'
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.debug e.message
        prep_edit
        render action: :edit
      end
    end
  end

  def create
    @driver = Driver.new 
    authorize! :create, Driver
    
    new_attrs = driver_params
    is_alt_address_blank = check_blank_alt_address
    if is_alt_address_blank
      new_attrs = new_attrs.except(:alt_address_attributes)
    end

    is_emergency_contact_blank = check_blank_emergency_contact
    is_geocoded_address_blank = check_blank_emergency_contact_geocoded_address
    if is_emergency_contact_blank
      new_attrs = new_attrs.except(:emergency_contact_attributes)
    else
      new_attrs[:emergency_contact_attributes] = new_attrs[:emergency_contact_attributes].except(:geocoded_address_attributes) if is_geocoded_address_blank
    end

    @driver.attributes = new_attrs
    @driver.alt_address = nil if is_alt_address_blank
    if is_emergency_contact_blank
      @driver.emergency_contact = nil 
    else
      if is_geocoded_address_blank
        @driver.emergency_contact.geocoded_address = nil
      elsif @driver.emergency_contact.geocoded_address.present?
        @driver.emergency_contact.geocoded_address.the_geom = Address.compute_geom(params[:lat], params[:lon])
      end
    end

    @driver.provider = current_provider

    # "Create a login for this driver": build the user here so the whole
    # driver is set up on one page. The user and the driver save together.
    @new_user_attrs = new_user_params
    new_user = nil
    new_password = nil
    if @new_user_attrs[:mode] == "new"
      authorize! :create, User
      new_user, new_password = build_driver_user(@new_user_attrs)
      @driver.user = new_user
    end

    if !@driver.is_all_valid?(current_provider_id) || (new_user && !new_user.valid?)
      @driver.errors.add(:user, "could not be created: #{new_user.errors.full_messages.to_sentence}") if new_user && !new_user.valid?
      prep_edit
      render action: :new
    else
      begin
        Driver.transaction do
          if new_user
            new_user.save!
            Role.create!(user: new_user, provider: current_provider, level: Role::USER_LEVEL)
          end
          @driver.save!
        end
        flash[:driver_password] = new_password if new_password
        redirect_to @driver, notice: 'Driver was successfully created.'
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.debug e.message
        @driver.errors.add(:base, e.message)
        prep_edit
        render action: :new
      end
    end
  end

  # No email ever reaches a driver, so a forgotten tablet password is fixed
  # here by a dispatcher: a new one is generated and shown once.
  def reset_password
    user = @driver.user
    return redirect_to(@driver, alert: "This driver has no login.") unless user && !user.deleted?
    authorize! :edit, user
    password = User.generate_password
    user.password = password
    user.password_confirmation = password
    if user.save
      flash[:driver_password] = password
      redirect_to @driver, notice: "New password set for #{user.username}."
    else
      redirect_to @driver, alert: "Could not reset the password: #{user.errors.full_messages.to_sentence}"
    end
  end

  def destroy
    @driver.destroy
    redirect_to drivers_path, notice: 'Driver was successfully deleted.'
  end

  def delete_photo
    @driver = Driver.find_by_id(params[:id])

    authorize! :update, @driver

    @driver.photo.try(:destroy!)

    redirect_to @driver, :notice => "Photo has been deleted."
  end

  def inactivate
    @driver = Driver.find_by_id(params[:id])

    authorize! :update, @driver
    
    prev_active_text = @driver.active_status_text
    prev_reason = @driver.active_status_changed_reason

    @driver.assign_attributes driver_inactivate_params

    if @driver.inactivated?
      if @driver.permanent_inactivated?
        @driver.inactivated_start_date = nil
        @driver.inactivated_end_date = nil
      else
        if @driver.inactivated_end_date.present? && !@driver.inactivated_start_date.present?
          @driver.inactivated_start_date = Date.today.in_time_zone
        end
      end
    else
      @driver.active_status_changed_reason = nil  
    end

    if @driver.changed?
      TrackerActionLog.driver_active_status_changed(@driver, current_user, prev_active_text, prev_reason)
    end

    @driver.save(validate: false)

    redirect_to @driver
  end

  def reactivate
    @driver = Driver.find(params[:id])
    authorize! :edit, @driver

    prev_active_text = @driver.active_status_text
    prev_reason = @driver.active_status_changed_reason

    @driver.reactivate!
    TrackerActionLog.driver_active_status_changed(@driver, current_user, prev_active_text, prev_reason)

    redirect_to @driver
  end

  def availability
    @readonly = true
    @driver = Driver.find_by_id(params[:id])
  end

  def availability_forecast
    @default_date = if params[:date]
      Date.parse params[:date]
    elsif session[:date]
      Date.parse session[:date]
    else
      Date.today
    end
        
  end

  def daily_availability_forecast
    session[:date] = params[:date]
    @date = Date.parse params[:date]
  end

  def assign_runs
    if @driver 
      run = Run.find_by_id(params[:run_id])
      if run 
        # first unassign other conflicting runs if any
        unless params[:conflicting_run_ids].blank?
          conflicting_runs = Run.where(id: params[:conflicting_run_ids].split(',')) 
          conflicting_runs.update_all(driver_id: nil)
        end

        run.driver = driver
        run.save(validate: false)
      end
    end
  end

  def unassign_runs
    if @driver
      @runs = Run.where(id: (params[:run_ids] || "").split(','))
      if @runs.any?
        @runs.update_all(driver_id: nil)
      end
    end
  end

  private

  DRIVER_EMAIL_DOMAIN = "drivers.gcrpc.org".freeze   # placeholder addresses, same as ops/maintenance/provision-driver-users.rb

  def new_user_params
    raw = params.dig(:driver, :new_user)
    return {} unless raw.respond_to?(:permit)
    raw.permit(:mode, :first_name, :last_name, :username, :email).to_h.symbolize_keys
  end

  def build_driver_user(attrs)
    password = User.generate_password
    username = attrs[:username].to_s.strip.downcase
    username = default_username(attrs[:first_name], attrs[:last_name]) if username.blank?
    email = attrs[:email].to_s.strip.presence || "#{username}@#{DRIVER_EMAIL_DOMAIN}"
    user = User.new(first_name: attrs[:first_name].to_s.strip, last_name: attrs[:last_name].to_s.strip,
                    username: username, email: email, password: password, password_confirmation: password,
                    current_provider: current_provider)
    user.user_address = nil if user.respond_to?(:user_address=)
    [user, password]
  end

  def default_username(first, last)
    f = first.to_s.downcase.gsub(/[^a-z]/, "")
    l = last.to_s.downcase.gsub(/[^a-z]/, "")
    base = "#{f}#{l[0]}"
    base = "driver" if base.blank?
    candidate = base
    n = 1
    while User.with_deleted.exists?(username: candidate)
      n += 1
      candidate = "#{base}#{n}"
    end
    candidate
  end

  def prep_edit(readonly: false)
    @readonly = readonly
    
    @available_users = @driver.provider.users - User.drivers(@driver.provider)
    @available_users << @driver.user if @driver.user
    @available_users = @available_users.sort_by(&:name_with_username) 
    
    @driver.address ||= @driver.build_address(provider_id: current_provider_id)
    @driver.alt_address ||= @driver.build_alt_address(provider_id: current_provider_id) 
    
    unless readonly
      @driver.build_photo unless @driver.photo.present?
    end
  end
  
  def driver_params
    params.require(:driver).permit(
      :paid, 
      :email, 
      :user_id,
      :phone_number,
      :alt_phone_number,
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
      ],
      :alt_address_attributes => [
        :address,
        :building_name,
        :city,
        :name,
        :provider_id,
        :state,
        :zip,
        :notes
      ],
      :emergency_contact_attributes => [
        :name,
        :phone_number,
        :relationship,
        :geocoded_address_attributes => [
          :provider_id,
          :address,
          :city,
          :state,
          :zip
        ]
      ]
    )
  end

  def driver_inactivate_params
    params.require(:driver).permit(
      :active,
      :inactivated_start_date,
      :inactivated_end_date,
      :active_status_changed_reason
    )
  end

  def check_blank_alt_address
    alt_address_params = driver_params[:alt_address_attributes]
    is_blank = true
    alt_address_params.keys.each do |key|
      next if key.to_s == 'provider_id'
      unless alt_address_params[key].blank?
        is_blank = false
        break
      end
    end if alt_address_params

    is_blank
  end

  def check_blank_emergency_contact
    contact_params = driver_params[:emergency_contact_attributes]
    is_blank = true
    contact_params.keys.each do |key|
      if key.to_s == 'geocoded_address_attributes'
        unless check_blank_emergency_contact_geocoded_address
          is_blank = false
          break
        end
      else
        unless contact_params[key].blank?
          is_blank = false
          break
        end
      end
    end if contact_params
    
    is_blank
  end

  def check_blank_emergency_contact_geocoded_address
    is_blank = true
    contact_params = driver_params[:emergency_contact_attributes]

    unless contact_params.blank?
      geocoded_address_params = contact_params[:geocoded_address_attributes]
      
      geocoded_address_params.keys.each do |key|
        next if key.to_s == 'provider_id'
        unless geocoded_address_params[key].blank?
          is_blank = false
          break
        end
      end if geocoded_address_params
    end

    is_blank
  end
end
