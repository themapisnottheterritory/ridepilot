class VehiclesController < ApplicationController
  load_and_authorize_resource except: [:update_initial_mileage, :inactivate, :reactivate, :start_disposition, :record_disposal, :cancel_disposition]

  def index
    @vehicles = @vehicles.default_order.for_provider(current_provider.id)
    # buses being moved to disposition are out of service but fleet still tracks them, so they stay listed
    @vehicles = @vehicles.where("vehicles.active = ? or vehicles.disposition_status = ?", true, "pending") if params[:show_inactive] != 'true'
  end

  def show
    @readonly = true
  end

  def new
    @vehicle.provider = current_provider
  end

  def edit; end

  def update
    new_attrs = vehicle_params
    old_garage = @vehicle.garage_address
    picked = picked_garage
    is_garage_address_blank = !picked && check_blank_garage_address

    if picked
      new_attrs = new_attrs.except(:garage_address_attributes)
    elsif is_garage_address_blank
      prev_garage_address = @vehicle.garage_address
      @vehicle.garage_address_id = nil
      new_attrs = new_attrs.except(:garage_address_attributes)
    elsif old_garage.try(:named?)
      # "Other address": this bus gets its own, and the shared garage stays as it is
      @vehicle.garage_address_id = nil
      new_attrs = new_attrs.merge(garage_address_attributes: new_attrs[:garage_address_attributes].to_h.except("id", :id).merge(name: nil))
    end

    @vehicle.assign_attributes new_attrs

    if picked
      # linked after the save, by GarageMove
    elsif !params[:address_lat].blank? && !params[:address_lon].blank?
      @vehicle.build_garage_address.the_geom = Address.compute_geom(params[:address_lat], params[:address_lon])
    elsif @vehicle.garage_address.present?
      @vehicle.garage_address.the_geom = Address.compute_geom(params[:lat], params[:lon])
    end

    if !@vehicle.is_all_valid?(current_provider_id)
      render action: :edit
    else
      begin      
        Vehicle.transaction do
          @vehicle.save!
          # a named garage is shared by other buses: never delete it
          prev_garage_address.destroy if is_garage_address_blank && prev_garage_address.present? && !prev_garage_address.try(:named?)
        end
        notice = 'Vehicle was successfully updated.'
        if picked && picked.id != old_garage.try(:id)
          moved = GarageMove.new(@vehicle, picked, current_user, from: old_garage).call
          notice += " It now lives at #{picked.name}; #{moved[:runs]} upcoming #{'run'.pluralize(moved[:runs])} now start and end there" +
                    (moved[:republished] > 0 ? " (#{moved[:republished]} republished to the tablet)." : ".")
        elsif !picked && @vehicle.garage_address_id != old_garage.try(:id) && @vehicle.garage_address
          GarageMove.new(@vehicle, @vehicle.garage_address, current_user, from: old_garage).call
        end
        redirect_to @vehicle, notice: notice
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.debug e.message
        render action: :edit
      end
    end
  end

  def create
    new_attrs = vehicle_params
    picked = picked_garage
    is_garage_address_blank = !picked && check_blank_garage_address
    if is_garage_address_blank || picked
      new_attrs = new_attrs.except(:garage_address_attributes)
    end

    @vehicle.attributes = new_attrs

    if picked
      @vehicle.garage_address_id = picked.id
    elsif is_garage_address_blank
      @vehicle.garage_address = nil
    elsif !params[:address_lat].blank? && !params[:address_lon].blank?
      @vehicle.build_garage_address.the_geom = Address.compute_geom(params[:address_lat], params[:address_lon])
    elsif @vehicle.garage_address.present?
      @vehicle.garage_address.the_geom = Address.compute_geom(params[:lat], params[:lon])
    end

    @vehicle.provider = current_provider
    if @vehicle.is_all_valid?(current_provider_id) && @vehicle.save
      redirect_to @vehicle, notice: 'Vehicle was successfully created.'
    else
      render action: :new
    end
  end

  def destroy
    @vehicle.destroy
    redirect_to vehicles_path, notice: 'Vehicle was successfully deleted.'
  end

  def edit_initial_mileage
    @vehicle = Vehicle.find_by_id(params[:id])
    authorize! :edit, @vehicle
  end

  def update_initial_mileage
    @vehicle = Vehicle.find_by_id(params[:id])
    authorize! :edit, @vehicle

    prev_mileage = @vehicle.initial_mileage
    @vehicle.assign_attributes change_initial_mileage_params

    respond_to do |format|
      format.html {
        if @vehicle.initial_mileage_change_reason.blank?
          flash.now[:error] = "Please provide a reason."
          render action: :edit_initial_mileage
        else
          @vehicle.save(validate: false)
          TrackerActionLog.change_vehicle_initial_mileage @vehicle, current_user, prev_mileage
          redirect_to @vehicle, notice: "Initial mileage has been updated."
        end
      }
    end
  end

  def inactivate
    @vehicle = Vehicle.find_by_id(params[:id])

    authorize! :update, @vehicle
    
    prev_active_text = @vehicle.active_status_text
    prev_reason = @vehicle.active_status_changed_reason

    @vehicle.assign_attributes vehicle_inactivate_params

    if @vehicle.inactivated?
      if @vehicle.permanent_inactivated?
        @vehicle.inactivated_start_date = nil
        @vehicle.inactivated_end_date = nil
      else
        if @vehicle.inactivated_end_date.present? && !@vehicle.inactivated_start_date.present?
          @vehicle.inactivated_start_date = Date.today.in_time_zone
        end
      end
    else
      @vehicle.active_status_changed_reason = nil  
    end

    if @vehicle.changed?
      TrackerActionLog.vehicle_active_status_changed(@vehicle, current_user, prev_active_text, prev_reason)
    end

    @vehicle.save(validate: false)

    redirect_to @vehicle
  end

  def reactivate
    @vehicle = Vehicle.find(params[:id])
    authorize! :edit, @vehicle

    prev_active_text = @vehicle.active_status_text
    prev_reason = @vehicle.active_status_changed_reason

    @vehicle.reactivate!
    TrackerActionLog.vehicle_active_status_changed(@vehicle, current_user, prev_active_text, prev_reason)

    redirect_to @vehicle
  end

  # Tony (fleet), 2026-10-02: "Move to disposition". The bus goes out of service for good
  # (permanently inactive, so dispatch stops offering it) but stays on the Vehicles list
  # with a Disposition badge until Record disposal says how it left the fleet.
  def start_disposition
    @vehicle = Vehicle.find(params[:id])
    authorize! :update, @vehicle
    prev_active_text = @vehicle.active_status_text
    prev_reason = @vehicle.active_status_changed_reason
    on = (Date.parse(params[:disposition_started_on].to_s) rescue Time.zone.today)
    note = params[:disposition_notes].to_s.strip.first(2000)
    @vehicle.assign_attributes(disposition_status: "pending", disposition_started_on: on, disposition_notes: note.presence,
                               active: false, inactivated_start_date: nil, inactivated_end_date: nil,
                               active_status_changed_reason: ["Moved to disposition", note.presence].compact.join(": "))
    TrackerActionLog.vehicle_active_status_changed(@vehicle, current_user, prev_active_text, prev_reason)
    @vehicle.save(validate: false)
    runs = @vehicle.upcoming_runs.count
    redirect_to @vehicle, notice: "#{@vehicle.name} is moved to disposition and out of service." +
      (runs.positive? ? " It is still on #{runs} upcoming run#{'s' if runs > 1}: give #{runs > 1 ? 'them' : 'it'} another bus." : "")
  end

  def record_disposal
    @vehicle = Vehicle.find(params[:id])
    authorize! :update, @vehicle
    d = params.require(:disposal)
    @vehicle.assign_attributes(
      disposition_status: "disposed",
      disposed_on: (Date.parse(d[:disposed_on].to_s) rescue Time.zone.today),
      disposition_started_on: @vehicle.disposition_started_on || Time.zone.today,
      disposition_method: Vehicle::DISPOSITION_METHODS.include?(d[:disposition_method]) ? d[:disposition_method] : "Other",
      disposition_odometer: d[:disposition_odometer].to_s.delete(",").presence&.to_i,
      disposition_proceeds: d[:disposition_proceeds].to_s.delete(",$").presence,
      disposition_notes: d[:disposition_notes].to_s.strip.first(2000).presence || @vehicle.disposition_notes,
      active: false)
    @vehicle.save(validate: false)
    redirect_to @vehicle, notice: "Disposal recorded: #{@vehicle.name}, #{@vehicle.disposition_method.downcase} on #{@vehicle.disposed_on.strftime('%b %-d, %Y')}."
  end

  # Moved by mistake, or the bus is kept after all: back in service, disposition cleared.
  def cancel_disposition
    @vehicle = Vehicle.find(params[:id])
    authorize! :update, @vehicle
    prev_active_text = @vehicle.active_status_text
    prev_reason = @vehicle.active_status_changed_reason
    @vehicle.assign_attributes(disposition_status: nil, disposition_started_on: nil, disposed_on: nil, disposition_method: nil,
                               disposition_odometer: nil, disposition_proceeds: nil, disposition_notes: nil)
    @vehicle.reactivate!
    TrackerActionLog.vehicle_active_status_changed(@vehicle, current_user, prev_active_text, prev_reason)
    redirect_to @vehicle, notice: "#{@vehicle.name} is back in service."
  end

  private

  def vehicle_params
    params.require(:vehicle).permit(
      :name, 
      :year, 
      :make, 
      :model, 
      :license_plate, 
      :vin, 
      :reportable,
      :is_5310_reportable,
      :air_brake,
      :insurance_coverage_details, 
      :ownership, 
      :responsible_party, 
      :registration_expiration_date, 
      :accessibility_equipment, 
      :wheelchair_lift,
      :mobility_device_accommodations,
      :initial_mileage,
      :garage_phone_number,
      :vehicle_maintenance_schedule_type_id,
      :vehicle_type_id,
      :garage_address_attributes => [
        :provider_id,
        :address,
        :city,
        :state,
        :zip
      ])
  end

  def vehicle_inactivate_params
    params.require(:vehicle).permit(
      :active,
      :inactivated_start_date,
      :inactivated_end_date,
      :active_status_changed_reason
    )
  end

  def change_initial_mileage_params
    params.require(:vehicle).permit(:initial_mileage, :initial_mileage_change_reason)
  end

  # The Garage list on the bus form: a named garage of this agency, or nil for
  # "Other address" (the address fields, as before).
  def picked_garage
    id = params[:garage_choice].to_s
    return nil unless id.match?(/\A\d+\z/)
    GarageAddress.named.usable.where(provider_id: @vehicle.provider_id || current_provider_id).find_by(id: id)
  end

  def check_blank_garage_address
    address_params = vehicle_params[:garage_address_attributes]
    is_blank = true
    address_params.keys.each do |key|
      next if key.to_s == 'provider_id'
      unless address_params[key].blank?
        is_blank = false
        break
      end
    end if address_params

    is_blank && params[:address_lat].blank? && params[:address_lon].blank?
  end
  
end
