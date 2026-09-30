class DispatchersController < ApplicationController
  before_action :authorization

  def index
    Date.beginning_of_week= :sunday
    filters_hash = runs_trips_params || {}
    filters_hash.delete(:dispatch_service_mode) unless filters_hash[:dispatch_service_mode].to_s.in?(DISPATCH_SERVICE_MODES)
    update_sessions(filters_hash.except(:start, :end))
    update_unassigned_trip_type_session

    # by default, select all trip results
    unless session[:trip_result_id].present?
      session[:trip_result_id] = [TripResult::UNSCHEDULED_ID, TripResult::SHOW_ALL_ID] + TripResult.pluck(:id).uniq
    end
    
    query_trips_runs
    prepare_unassigned_trip_schedule_options

    @run_trip_day    = Utility.new.parse_date(session[:run_trip_day])

    respond_to do |format|
      format.html
    end
  end

  def schedule
    @run = Run.find_by_id params[:run_id]
    @prev_run = Run.find_by_id(params[:prev_run_id]) if params[:prev_run_id].present?
    if @run
      trip = Trip.find_by_id params[:trip_id]

      if @prev_run && trip.itineraries.finished.any?
        @has_finished_itinerary = true
      end

      unless @has_finished_itinerary
        from_label = if @prev_run
          @prev_run.name
        elsif trip.is_stand_by
          "Standby"
        elsif trip.cab?
          "Cab"
        else
          "Unscheduled"
        end

        @scheduler = TripScheduler.new(params[:trip_id], params[:run_id])
        @scheduler.execute

        #if @prev_run
        #  TrackerActionLog.trips_removed_from_run(@prev_run, [trip], current_user)
        #end

        #TrackerActionLog.trips_added_to_run(@run, [trip], current_user)
            
        TrackerActionLog.trip_scheduled_to_run(trip, current_user, from_label, @run.name)
      end
    
      query_trips_runs
      prepare_unassigned_trip_schedule_options
    end
  end

  def schedule_multiple
    @target_trip_ids = params[:trip_ids].split(',') if params[:trip_ids].present?
  
    if @target_trip_ids && @target_trip_ids.any?
      @new_status_id = params[:status_id].to_i if params[:status_id]
      if [Run::UNSCHEDULED_RUN_ID, Run::STANDBY_RUN_ID, Run::CAB_RUN_ID].include? @new_status_id
        unschedule_trips
      elsif @new_status_id == Run::TRIP_UNMET_NEED_ID
        Trip.where(id: @target_trip_ids).move_to_unmet!
      else
        @errors = []
        @error_trip_count = 0
        @target_run = Run.find_by_id @new_status_id
        to_label = @target_run.name

        Trip.where(id: @target_trip_ids).each do |trip|
          from_label = if trip.run
            trip.run.name
          elsif trip.is_stand_by
            "Standby"
          elsif trip.cab?
            "Cab"
          else
            "Unscheduled"
          end
          
          trip_id = trip.id
          scheduler = TripScheduler.new(trip_id, @new_status_id)
          scheduler.execute
          
          if scheduler.errors.any?
            @error_trip_count += 1
            @errors += scheduler.errors
          else
            TrackerActionLog.trip_scheduled_to_run(trip, current_user, from_label, to_label)
          end
        end

        #if @target_run
        #  TrackerActionLog.trips_added_to_run(@target_run, Trip.where(id: assigned_trip_ids), current_user)
        #end

        @errors.uniq!
      end

      query_trips_runs
      prepare_unassigned_trip_schedule_options
    end
  end

  def unschedule
    @prev_run = Run.find_by_id(params[:prev_run_id])
    @target_trip_ids = params[:trip_ids].split(',')
    if @target_trip_ids.any?
      @new_status_id = params[:run_id].to_i if params[:run_id]
      unschedule_trips

      #if @prev_run
      #  TrackerActionLog.trips_removed_from_run(@prev_run, Trip.where(id: @target_trip_ids), current_user)
      #end

      query_trips_runs
      prepare_unassigned_trip_schedule_options
    end
  end

  def publish_manifest
    @run = Run.find_by_id params[:run_id]

    # requires eta
    if @run.itineraries.where(eta: nil).any?
      calculate_eta
    end

    @run.publish_manifest!(@run.date == Date.today && !@run.complete? && @run.start_odometer && !@run.end_odometer)
  end

  def run_trips
    @run = Run.find_by_id params[:run_id]
  end

  def cancel_run
    @run = Run.find_by_id params[:run_id]
    if @run
      @run.cancel! 
      TrackerActionLog.cancel_run(@run, current_user)
    end

    query_trips_runs
    prepare_unassigned_trip_schedule_options
  end

  def load_trips
    update_unassigned_trip_type_session

    query_trips_runs
    prepare_unassigned_trip_schedule_options
  end

  def batch_change_same_run_trip_result
    @target_trips = Trip.where(id: params[:trip_ids].split(',')) if params[:trip_ids].present?

    if @target_trips && @target_trips.any?
      @target_run = @target_trips.first.run
      trip_result = TripResult.find_by_id(params[:trip_result_id])

      @target_trips.each do |trip|
        trip.trip_result = trip_result
        trip.result_reason = params[:result_reason]
        trip.save(validate: false)

        trip.post_process_trip_result_changed!(current_user)
      end

      query_trips_runs
      prepare_unassigned_trip_schedule_options
    end
  end

  def update_run_manifest_order
    @run = Run.find_by_id params[:run_id]
    itin_id = params[:itin_id]
    trip_id = itin_id.split('_')[1]
    itin_leg_flag = itin_id.split('_')[3]
    @itin = @run.itineraries.where(trip_id: trip_id, leg_flag: itin_leg_flag).first

    if @run && @itin && params[:manifest_order].present?
      if @itin.finish_time
        # you can't move a finished itin
        @has_finished_itinerary = true
      else
        new_order = params[:manifest_order].split(',').uniq
        # you can't move to before a finished itin
        idx = new_order.index(itin_id)
        if idx
          next_itin_id = new_order[idx+1]
          if next_itin_id
            next_itin_trip_id = next_itin_id.split('_')[1]
            next_itin_leg_flag = next_itin_id.split('_')[3]
            next_itin = @run.itineraries.where(trip_id: next_itin_trip_id, leg_flag: next_itin_leg_flag).first
            if next_itin && next_itin.finish_time
              @move_to_invalid_position = true
            end
          end
        end

        unless @move_to_invalid_position
          @run.manifest_order = new_order 
          @run.save(validate: false)
          @run.itineraries.clear_times! #clear itins times

          #TrackerActionLog.rearrange_trip_itineraries(@run, current_user)
        end
      end
    end
  end

  def eta
    @run = Run.find_by_id params[:run_id]

    calculate_eta
  end

  def update_slack_chart
    @run = Run.find_by_id params[:run_id]
  end
  
  private

  def authorization
    authorize! :read, Run, :provider_id => current_provider_id
    authorize! :read, Trip, :provider_id => current_provider_id
  end

  def update_unassigned_trip_type_session
    session[:unassigned_trip_status_id] = if params[:trip_status_id].present?
      params[:trip_status_id]
    else 
      session[:unassigned_trip_status_id] || Run::UNSCHEDULED_RUN_ID
    end
  end

  def query_trips_runs
    filters_hash = runs_trips_params || {}

    @runs = Run.not_cancelled.for_provider(current_provider_id).reorder(nil).default_order
    @runs = @runs.where(id: filters_hash[:run_id]) unless filters_hash[:run_id].blank?
    filter_runs

    @trips = Trip.has_scheduled_time.for_provider(current_provider_id).includes(:customer, :pickup_address, :run)
    .references(:customer, :pickup_address, :run).order(:pickup_time)
    .preload(ridership_mobilities: :mobility)   # mobility icon
    # Exclude trips with following result codes from trips-runs page
    exclude_trip_result_ids = TripResult.non_dispatchable_result_ids
    @trips = @trips.where("trip_result_id is NULL or trip_result_id not in (?)", exclude_trip_result_ids)
    filter_trips

    @unscheduled_trips = @trips.unscheduled
    @standby_trips = @trips.standby
    @cab_trips = @trips.for_cab
  end

  def prepare_unassigned_trip_schedule_options
    @schedule_options = []
    case session[:unassigned_trip_status_id].try(:to_i)
    when Run::UNSCHEDULED_RUN_ID
      @schedule_options += [[Run::STANDBY_RUN_ID, 'Standby']]
      @schedule_options += [[Run::CAB_RUN_ID, 'Cab']] if current_provider.try(:cab_enabled?)
    when Run::STANDBY_RUN_ID
      @schedule_options += [[Run::UNSCHEDULED_RUN_ID, 'Unscheduled']]
      @schedule_options += [[Run::CAB_RUN_ID, 'Cab']] if current_provider.try(:cab_enabled?)
    when Run::CAB_RUN_ID
      @schedule_options += [[Run::STANDBY_RUN_ID, 'Standby']]
      @schedule_options += [[Run::UNSCHEDULED_RUN_ID, 'Unscheduled']]
    end

    @schedule_options += @runs.incomplete.where.not(service_mode: "fixed_route").pluck(:id, :name)

    if session[:unassigned_trip_status_id].try(:to_i) == Run::STANDBY_RUN_ID
      @schedule_options += [[Run::TRIP_UNMET_NEED_ID, 'Unmet Need']] 
    end

    @schedule_options.compact
  end

  def unschedule_trips
    @need_to_update_trips_panel = @new_status_id == session[:unassigned_trip_status_id].try(:to_i)
    target_trips = Trip.where(id: @target_trip_ids)
    @trip_ids_with_finished_itins = Itinerary.where(trip_id: @target_trip_ids).finished.pluck(:trip_id).uniq
    target_trips = target_trips.where.not(id: @trip_ids_with_finished_itins) # ignore trips with finished itins
    if target_trips.any?
      prev_run_ids = target_trips.pluck(:run_id).uniq
      case @new_status_id
      when Run::STANDBY_RUN_ID
        target_trips.update_all(cab: false, is_stand_by: true, run_id: nil)
      when Run::CAB_RUN_ID
        target_trips.update_all(cab: true, is_stand_by: false, run_id: nil)
      when Run::UNSCHEDULED_RUN_ID
        target_trips.update_all(cab: false, is_stand_by: false, run_id: nil)
      end

      # remove trip from prev_run manifest order
      if prev_run_ids.any?
        Run.where(id: prev_run_ids).each do |prev_run|
          @target_trip_ids.each do |trip_id|
            prev_run.delete_trip_manifest!(trip_id)
          end
        end
      end
    end
  end

  def calculate_eta
    if @run
      @eta_info = RunStatsCalculator.new(@run.id).process_eta
    end
  end

  def filter_trips
    trip_filter = TripFilter.new(@trips, trip_sessions)
    @trips = trip_filter.filter!
  end

  def filter_runs
    run_filter = RunFilter.new(@runs, run_sessions)
    @runs = run_filter.filter!
  end

  def runs_trips_params
    raw_params = params[:run_trip_filters] || {}
    
    if params[:run_trip_filters]
      raw_params[:run_trip_day] = Date.today.in_time_zone.to_i if raw_params[:run_trip_day].blank?
    else
      if session[:run_trip_day]
        raw_params[:run_trip_day] = Utility.new.parse_date(session[:run_trip_day]).try(:to_i) 
      else
        raw_params[:run_trip_day] = Date.today.in_time_zone.to_i
      end
    end

    raw_params
  end

  def update_sessions(params = {})
    params.each do |key, val|
      session[key] = val if !val.nil?
    end
  end

  # Dispatch shows demand-response runs unless the person picks otherwise
  # (fixed-route runs can't take a trip; 27 of them buried the 28 DR runs).
  DISPATCH_SERVICE_MODES = %w[demand_response fixed_route all].freeze

  def dispatch_service_mode
    session[:dispatch_service_mode].presence_in(DISPATCH_SERVICE_MODES) || "demand_response"
  end

  def run_sessions
    {
      start: session[:run_trip_day],
      end: session[:run_trip_day], 
      run_id: session[:run_id], 
      run_result_id: session[:run_result_id],
      service_mode: (dispatch_service_mode unless dispatch_service_mode == "all")
    }
  end

  def trip_sessions
    {
      start: session[:run_trip_day],
      end: session[:run_trip_day],  
      run_id: session[:run_id], 
      trip_result_id: session[:trip_result_id], 
      status_id: session[:status_id]
    }
  end

  def add_cab_run(runs)
    runs + [Run.fake_cab_run]
  end

  def add_unscheduled_run(runs)
    runs + [Run.fake_unscheduled_run]
  end
end