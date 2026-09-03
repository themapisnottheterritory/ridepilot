class Api::V1::Driver::RunsController < Api::V1::Driver::BaseController

  def index
    get_runs
    opts = {}
    opts[:include] = [:vehicle]
    render success_response(@runs, opts)
  end

  def show
    @run = Run.find_by_id(params[:id])
    opts = {}
    opts[:include] = [:vehicle]
    render success_response(@run, opts)
  end

  # Start run
  def start
    @run = Run.find_by_id(params[:id])

    if @run
      @run.driver_notes = params[:driver_notes]
      @run.start_odometer = params[:start_odometer]
      current_time = DateTime.current
      @run.actual_start_time = current_time
      @run.save(validate: false)

      # start leg completed
      @run.itineraries.run_begin.update_all(status_code: Itinerary::STATUS_COMPLETED, finish_time: current_time)
    end

    render success_response({})
  end

  # End run
  def end
    @run = Run.find_by_id(params[:id])

    if @run
      @run.end_odometer = params[:end_odometer]
      current_time = DateTime.current
      @run.actual_end_time = current_time
      @run.save(validate: false)

      # end leg completed
      @run.itineraries.run_end.update_all(status_code: Itinerary::STATUS_COMPLETED, finish_time: current_time)
    end

    render success_response({})
  end

  def update_from_address
    @run = Run.find_by_id(params[:id])
    if @run
      addr = parse_address
      addr.save
      @run.update_column(:from_garage_address_id, addr.id)
    end

    render success_response({})
  end

  def update_to_address
    @run = Run.find_by_id(params[:id])
    if @run
      addr = parse_address
      addr.save
      @run.update_column(:to_garage_address_id, addr.id)
    end

    render success_response({})
  end

  # find active run and active itin
  def driver_run_data
    if @driver
      get_runs
      active_run = @runs.where.not(start_odometer: nil)
        .where(end_odometer: nil)
        .default_order.first

      if active_run
        public_itins = active_run.public_itineraries
        active_public_itin = public_itins.non_finished.first
        active_itin = active_public_itin.try(:itinerary)
        idx = public_itins.index(active_public_itin)
        next_itin = public_itins[idx + 1].try(:itinerary) if idx

        last_read_message_id = ChatReadReceipt.for_today.where(read_by_id: current_user.try(:id), run_id: active_run.id).reorder(created_at: :desc).first.try(:message_id)
        last_message_id = RoutineMessage.for_today.where.not(sender_id: current_user.try(:id)).where(run_id: active_run.id).reorder(created_at: :desc).first.try(:id)

        has_unread_chat = last_read_message_id != last_message_id
      end
    end

    itin_opts = {}
    itin_opts[:include] = [:address]

    provider = @driver.provider
    render success_response({
      provider_id: provider.try(:id),
      has_unread_chat: has_unread_chat,
      timezone: Time.zone.name,
      active_run: active_run ? RunSerializer.new(active_run).serializable_hash : nil,
      active_itin: active_itin ? ItinerarySerializer.new(active_itin, itin_opts).serializable_hash : nil,
      next_itin: next_itin ? ItinerarySerializer.new(next_itin, itin_opts).serializable_hash : nil,
      timezone_offset: (DateTime.current.utc_offset / 3600),
      map_center_lat: (provider && provider.viewport_center ? provider.viewport_center.y : GOOGLE_MAP_DEFAULTS[:viewport][:center_lat]),
      map_center_lng: (provider && provider.viewport_center ? provider.viewport_center.x : GOOGLE_MAP_DEFAULTS[:viewport][:center_lng]),
      map_zoom: (provider && provider.viewport_zoom || GOOGLE_MAP_DEFAULTS[:viewport][:zoom] || 10)
      })
  end

  # Unit confirmation. At run start the driver either confirms the assigned
  # vehicle (vehicle_id blank or equal to the run's) or names the unit actually
  # being driven. Drivers take a different bus all the time, and everything
  # downstream (DVIR, odometer, maintenance events, AVL, NTD miles) keys off the
  # run's vehicle, so a change is paper-trailed, written to the run's action
  # log, and announced to dispatch through the run's chat.
  def update_vehicle
    @run = Run.find_by(id: params[:id], driver: @driver)
    return render fail_response(status: 404, run: "Run not found.") unless @run
    return render fail_response(status: 422, vehicle: "This run has already ended.") if @run.end_odometer.present?

    requested_id = params[:vehicle_id].presence.try(:to_i)
    if requested_id.nil? || requested_id == @run.vehicle_id
      return render fail_response(status: 422, vehicle: "No unit is assigned to this run. Choose the unit you are driving.") if @run.vehicle.nil?
      @run.update_column(:vehicle_confirmed_at, DateTime.current)
      return render success_response(@run, include: [:vehicle])
    end

    vehicle = Vehicle.for_provider(@run.provider_id).where(active: true).find_by(id: requested_id)
    return render fail_response(status: 404, vehicle: "That unit is not in the active fleet.") unless vehicle

    # Same unit already rolling on someone else's overlapping run: block, the
    # driver has to sort it out with dispatch. Merely assigned but not started:
    # allow it and let dispatch know (they will reassign the other run).
    overlapping = Run.other_overlapped_runs(@run).where(vehicle_id: vehicle.id).includes(:driver)
    rolling = overlapping.where.not(start_odometer: nil).where(end_odometer: nil).first
    if rolling
      who = rolling.driver.try(:user_name) || rolling.name
      return render fail_response(status: 422, vehicle: "Unit #{vehicle.name} is on #{who}'s run. Call dispatch.")
    end
    also_assigned = overlapping.where(start_odometer: nil).first

    previous = @run.vehicle
    @run.vehicle = vehicle
    @run.vehicle_confirmed_at = DateTime.current
    PaperTrail.request(whodunnit: @driver.user_id.to_s) do
      @run.save(validate: false)
    end
    TrackerActionLog.update_run(@run, @driver.user, { 'vehicle_id' => [previous.try(:id), vehicle.id] })

    body = "Taking unit #{vehicle.name} instead of #{previous ? "unit #{previous.name}" : 'the unassigned unit'} for run #{@run.name}."
    body += " Unit #{vehicle.name} was assigned to #{also_assigned.driver.try(:user_name) || also_assigned.name} (not started)." if also_assigned
    RoutineMessage.create(provider_id: @run.provider_id, driver: @driver, sender: @driver.user, run_id: @run.id, body: body)

    render success_response(@run, include: [:vehicle])
  end

  def manifest_published_at
    @run = Run.find_by_id(params[:id])
    render success_response({
      manifest_published_at: @run.try(:manifest_published_at)
      })
  end

  private

  def get_runs
    @runs = Run.where(date: Date.today, driver: @driver).default_order.joins(:public_itineraries).group('runs.id')
  end

  def parse_address
    address = GarageAddress.new(address_params)
    if params[:address][:longitude] && params[:address][:latitude]
      address.the_geom = Address.compute_geom(params[:address][:latitude], params[:address][:longitude])
    end

    address
  end

  def address_params
    params.required(:address).permit(:address, :city, :state, :zip)
  end
end
