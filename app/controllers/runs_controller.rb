# a note on general run workflow:
# Runs are created as part of the trip scheduling 
# process; they're associated with a vehicle and
# a driver.  At the end of the day, the driver
# must update the run with post-run data like
# odometer start/end and no-shows.  That is 
# presented by my_runs and end_of_day

class RunsController < ApplicationController
  load_and_authorize_resource

  def index
    Date.beginning_of_week= :sunday

    @runs = Run.for_provider(current_provider_id).includes(:driver, :vehicle).reorder(nil).default_order
    filter_runs
    
    @drivers = Driver.where(:provider_id=>current_provider_id).default_order
    @vehicles = Vehicle.where(:provider_id=>current_provider_id).default_order
    @start_pickup_date = Time.zone.at(session[:runs_start].to_i).to_date
    @end_pickup_date = Time.zone.at(session[:runs_end].to_i).to_date
    @days_of_week = run_sessions[:days_of_week].blank? ? [0,1,2,3,4,5,6] : run_sessions[:days_of_week].split(',').map(&:to_i)

    if @start_pickup_date > @end_pickup_date
      flash.now[:alert] = TranslationEngine.translate_text(:from_date_cannot_later_than_to_date)
    else
      flash.now[:alert] = nil
    end


    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @runs }
      format.json { render :json => @runs }
    end
  end

  def new
    @run = Run.new
    @run.date = params[:date] unless params[:date].blank?
    @run.provider_id = current_provider_id
    setup_run
    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @trip }
    end
  end

  def uncompleted_runs
    @runs = Run.for_provider(current_provider_id).incomplete.order("date desc")
    render "index"
  end

  def show
    @readonly = true
    setup_run
  end

  def edit
    setup_run

    if @run.complete?
      render :show
    end
  end

  def create
    authorize! :manage, @run
    
    @run = Run.new(run_params)
    @run.provider = current_provider
    
    respond_to do |format|
      if @run.is_all_valid?(current_provider_id) && @run.save
        if @run.vehicle && @run.vehicle.garage_address 
          @run.from_garage_address = @run.vehicle.garage_address.dup
          @run.to_garage_address = @run.vehicle.garage_address.dup
          @run.save(validate: false)
        end

        TrackerActionLog.create_run(@run, current_user)
        format.html { 
          if params[:from_dispatch] == 'true'
            redirect_to dispatchers_path(run_id: @run.id), :notice => 'Run was successfully created.' 
          else
            redirect_to @run, :notice => 'Run was successfully created.' 
          end
        }
        format.xml  { render :xml => @run, :status => :created, :location => @run }
      else
        setup_run

        format.html { render :action => "new" }
        format.xml  { render :xml => @run.errors, :status => :unprocessable_entity }
      end
    end
  end

  def update    
    authorize! :manage, @run
    
    @run.assign_attributes run_params 
    changes = @run.changes   

    respond_to do |format|
      if @run.is_all_valid?(current_provider_id) && @run.save
        # update start&end location with vehicle garage
        if params[:use_vehicle_garage] == 'true' && @run.vehicle && @run.vehicle.garage_address 
          @run.from_garage_address = @run.vehicle.garage_address.dup
          @run.to_garage_address = @run.vehicle.garage_address.dup
          @run.save(validate: false)
        end

        TrackerActionLog.update_run(@run, current_user, changes)
        format.html { 
          if params[:from_dispatch] == 'true'
            redirect_to dispatchers_path(run_id: @run.id), :notice => 'Run was successfully updated.' 
          else
            redirect_to @run, :notice => 'Run was successfully updated.' 
          end
        }
        format.xml  { head :ok }
      else
        setup_run
        
        format.html { render :action => "edit" }
        format.xml  { render :xml => @run.errors, :status => :unprocessable_entity }
      end
    end
  end

  def destroy
    @run.destroy

    respond_to do |format|
      format.html { redirect_to(runs_path(date_range(@run)), :notice => 'Run was successfully deleted.') }
      format.xml  { head :ok }
    end
  end
  
  def for_date
    date = Date.parse params[:date]
    @runs = @runs.for_provider(current_provider_id).incomplete_on date
    if current_provider.try(:cab_enabled?)
      cab_run = Run.new :cab => true
      cab_run.id = -1
      @runs = @runs + [cab_run] 
    end
    render :json =>  @runs.to_json 
  end
  
  # Cancels multiple runs by id, removing associations with any trips on those runs
  def cancel_multiple
    @runs = Run.where(actual_start_time: nil).where(id: cancel_multiple_params[:run_ids].split(',').map(&:to_i))
    trips_removed = @runs.joins(:trips).size
    @runs.cancel_all
    
    @runs.each do |run|
      TrackerActionLog.cancel_run(run, current_user)
    end
    
    respond_to do |format|
      format.html { redirect_to(runs_path, notice: "#{trips_removed} trips successfully unscheduled from #{@runs.count} runs. (Started runs cannot be unscheduled.)")}
    end
  end
  
  # Destroys multiple runs by id, deleting them from the database
  def delete_multiple
    @runs = Run.where(actual_start_time: nil).where(id: delete_multiple_params[:run_ids].split(',').map(&:to_i))
    runs_destroyed = can?(:delete, Run) ? @runs.destroy_all : Run.none
    if runs_destroyed
      respond_to do |format|
        format.html { redirect_to(runs_path, notice: "#{runs_destroyed.count} runs successfully deleted. (Started runs cannot be deleted.)") }
      end
    end
  end

  def check_driver_vehicle_availability
    date = Date.parse params[:date] if !params[:date].blank?
    start_time = DateTime.parse params[:start_time] if !params[:start_time].blank?
    end_time = DateTime.parse params[:end_time] if !params[:end_time].blank?

    @is_vehicle_active = @is_driver_active = @is_driver_available = true

    @vehicle = Vehicle.find_by_id(params[:vehicle_id])
    if @vehicle && date
      @is_vehicle_active = @vehicle.active_for_date?(date)
    end

    @driver = Driver.find_by_id(params[:driver_id])
    if @driver && date 
      @is_driver_active = @driver.active_for_date?(date)
      if start_time && end_time
        @is_driver_available = @driver.available_between?(date, start_time.strftime('%H:%M'), end_time.strftime('%H:%M')) 
      end
    end
  end 

  def request_change_locations
  end

  def update_locations
    prev_from_address = @run.from_garage_address.try(:dup)
    prev_to_address = @run.to_garage_address.try(:dup)

    if !prev_from_address || !prev_from_address.same_lat_lng?(params[:from_garage_address_lat], params[:from_garage_address_lon])
      @run.build_from_garage_address(provider_id: current_provider_id)
      @run.from_garage_address.the_geom = Address.compute_geom(params[:from_garage_address_lat], params[:from_garage_address_lon])
    end

    if !prev_to_address || !prev_to_address.same_lat_lng?(params[:to_garage_address_lat], params[:to_garage_address_lon])
      @run.build_to_garage_address(provider_id: current_provider_id)
      @run.to_garage_address.the_geom = Address.compute_geom(params[:to_garage_address_lat], params[:to_garage_address_lon])
    end

    @run.attributes = run_params

    @run.save(validate: false)

    redirect_to run_path(@run)
  end

  def request_uncompletion
  end

  def uncomplete
    @run.set_incomplete!(params[:run][:uncomplete_reason], current_user)
    redirect_to run_path(@run)
  end

  def complete
    if @run.completable?
      @run.set_complete!(current_user)
    end

    redirect_to run_path(@run)
  end

  def assign_driver
    if @run 
      driver = Driver.find_by_id(params[:driver_id])
      if driver 
        # first unassign other conflicting runs if any
        unless params[:conflicting_run_ids].blank?
          conflicting_runs = Run.where(id: params[:conflicting_run_ids].split(',')) 
          conflicting_runs.update_all(driver_id: nil)
        end

        @run.driver = driver
        @run.save(validate: false)
      end
    end
  end

  def unassign_driver
    if @run
      @run.driver_id = nil
      @run.save(validate: false)
    end
  end

  def optimize
    authorize! :update, @run
    RouteOptimizeJob.perform_later(@run.id)
    respond_to do |format|
      format.json { render json: { status: "queued", run_id: @run.id } }
      format.html { redirect_to run_path(@run), notice: "Route optimization queued." }
    end
  end

  def reload_drivers
    @drivers = Driver.active.where(:provider_id=>current_provider_id).default_order
    date = Date.parse(params[:date]) rescue nil
    unless params[:from_time].blank?
      from_time = DateTime.parse(params[:date] + " " + params[:from_time]) rescue nil 
    end
    unless params[:to_time].blank?
      to_time = DateTime.parse(params[:date] + " " + params[:to_time]) rescue nil 
    end
    exclude_inactive_drivers(date, from_time, to_time)
  end

  def reload_vehicles
    @vehicles = Vehicle.active.where(:provider_id=>current_provider_id).default_order
    date = Date.parse(params[:date]) rescue nil
    exclude_inactive_vehicles(date)
  end
  
  private
  
  def setup_run
    @drivers = Driver.active.where(:provider_id=>@run.provider_id).default_order

    @vehicles = Vehicle.active.where(:provider_id=>@run.provider_id).default_order

    unless @readonly
      exclude_inactive_drivers(@run.date, @run.scheduled_start_time, @run.scheduled_end_time)
      exclude_inactive_vehicles(@run.date)
    end
  end

  def exclude_inactive_drivers(date, from_time, to_time)
    if date
      @drivers = @drivers.active_for_date(date)
      # exclude unavailable drivers for run time range
      if from_time && to_time
        driver_ids = []
        from_time_str = from_time.strftime('%H:%M')
        to_time_str = to_time.strftime('%H:%M')
        @drivers.each do |driver|
          driver_ids << driver.id if driver.available_between?(date, from_time_str, to_time_str) 
        end
        @drivers = @drivers.where(id: driver_ids)
      end
    end
  end

  def exclude_inactive_vehicles(date)
    if date
      @vehicles = @vehicles.active_for_date(date)
    end
  end

  def date_range(run)
    if run.date
      week_start = run.date.beginning_of_week
      {:start => week_start.to_time.to_i, :end => (week_start + 6.days).to_time.to_i } 
    end    
  end
  
  def run_params
    params.require(:run).permit(
      :name, 
      :date, 
      :start_odometer, 
      :end_odometer, 
      :scheduled_start_time, 
      :scheduled_end_time, 
      :unpaid_driver_break_time, 
      :vehicle_id, 
      :driver_id, 
      :paid, 
      :complete, 
      :actual_start_time, 
      :actual_end_time, 
      :from_garage_address_attributes => [
        :provider_id,
        :address,
        :city,
        :state,
        :zip
      ],
      :to_garage_address_attributes => [
        :provider_id,
        :address,
        :city,
        :state,
        :zip
      ]
    )
  end

  def filter_runs
    filters_hash = params[:run_filters] || {}
    
    update_sessions(filters_hash)

    run_filter = RunFilter.new(@runs, run_sessions)
    @runs = run_filter.filter!

    update_sessions({
      start: run_filter.filters[:start],
      end: run_filter.filters[:end],
      days_of_week: run_filter.filters[:days_of_week]
      })
  end

  def update_sessions(params = {})
    params.each do |key, val|
      session["runs_#{key}"] = val if !val.nil?
    end
  end

  def run_sessions
    {
      start: session[:runs_start],
      end: session[:runs_end], 
      driver_id: session[:runs_driver_id], 
      vehicle_id: session[:runs_vehicle_id],
      run_result_id: session[:runs_run_result_id], 
      days_of_week: session[:runs_days_of_week]
    }
  end
  
  def cancel_multiple_params
    params.require(:cancel_multiple_runs).permit(:run_ids)
  end
  
  def delete_multiple_params
    params.require(:delete_multiple_runs).permit(:run_ids)
  end
end
