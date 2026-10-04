class RepeatingRunsController < ApplicationController
  before_action :set_run, except: [:index, :new, :create]
  authorize_resource

  def index
    @runs = RepeatingRun.active.for_provider(current_provider_id).order(created_at: :desc)
  end

  def new
    @run = RepeatingRun.new(:provider_id => current_provider_id)

    prep_view
    
    respond_to do |format|
      format.html 
    end
  end

  def edit
    prep_view
    
    respond_to do |format|
      format.html 
    end
  end
  
  def show
    prep_view
    
    respond_to do |format|
      format.html
    end
  end

  def create
    @run = RepeatingRun.new(run_params)
    @run.provider = current_provider
    authorize! :manage, @run

    respond_to do |format|
      if @run.is_all_valid?(current_provider_id) && @run.save
        TrackerActionLog.create_subscription_run(@run, current_user)
        format.html {
          if params[:from_dispatch] == 'true'
            redirect_to recurring_dispatchers_path(run_id: @run.id), :notice => 'Run was successfully created.' 
          else
            redirect_to @run, :notice => 'Subscription run template was successfully created.'
          end
        }
      else
        prep_view
        format.html { render :action => "new" }
      end
    end

  end

  def update
    authorize! :manage, @run

    prev_schedule = @run.schedule
    @run.assign_attributes(run_params)
    changes = @run.changes
    respond_to do |format|
      if @run.is_all_valid?(current_provider_id) && @run.save
        TrackerActionLog.update_subscription_run(@run, current_user, changes, prev_schedule)
        format.html { 
          if params[:from_dispatch] == 'true'
            redirect_to recurring_dispatchers_path(run_id: @run.id), :notice => 'Run was successfully updated.' 
          else
            redirect_to @run, :notice => 'Subscription run template was successfully updated.'
          end  
        }
      else
        prep_view
        format.html { render :action => "edit"  }
      end
    end
  end

  def destroy
    @run.destroy

    respond_to do |format|
      format.html { redirect_to(repeating_runs_url) }
    end
  end

  private

  def set_run
    @run = RepeatingRun.find_by_id(params[:id])
  end
  
  def run_params
    params.require(:repeating_run).permit(
      :name, 
      :service_mode,
      :fixed_route_id,
      :scheduled_start_time, 
      :scheduled_end_time, 
      :vehicle_id, 
      :driver_id, 
      :unpaid_driver_break_time,
      :paid, 
      :repeats_sundays,
      :repeats_mondays,
      :repeats_tuesdays,
      :repeats_wednesdays,
      :repeats_thursdays,
      :repeats_fridays,
      :repeats_saturdays,
      :repetition_driver_id,
      :repetition_interval,
      :repetition_vehicle_id,
      :start_date,
      :end_date,
      :comments
    )
  end

  def prep_view
    @drivers = Driver.active.where(:provider_id=>@run.provider_id)
    @fixed_routes = FixedRoute.for_provider(@run.provider_id).active.default_order
    @vehicles = Vehicle.active.where(:provider_id=>@run.provider_id)
  end
end