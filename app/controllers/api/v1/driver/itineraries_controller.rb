class Api::V1::Driver::ItinerariesController < Api::V1::Driver::BaseController

  def index
    unless params[:run_id].blank?
      @run = Run.find_by_id params[:run_id]
    else
      @run = Run.where(date: Date.today, driver: @driver).incomplete.first
    end
    # No run (none today, or a stale run id): an empty manifest, not a 500.
    return render success_response(Itinerary.none) unless @run
    opts = {}
    opts[:include] = [:address]
    itins = Itinerary.unscoped.joins(:public_itinerary).where(public_itineraries: {run_id: @run.id}).order("public_itineraries.sequence")
    exclude_leg_ids = itins.dropoff.joins(trip: :trip_result).where(trip_results: {code: TripResult::NON_DISPATCHABLE_CODES}).pluck(:id).uniq
    itins = itins.where.not(id: exclude_leg_ids)
    render success_response(itins, opts)
  end

  def show
    @itin = Itinerary.find_by_id(params[:id])
    return render_itinerary_gone unless @itin

    opts = {}
    opts[:include] = [:address]
    render success_response(@itin, opts)
  end

  def update
    @itin = Itinerary.find_by_id(params[:id])
    return render_itinerary_gone unless @itin

    @itin.update(itin_params)

    opts = {}
    opts[:include] = [:address]
    render success_response(@itin, opts)
  end

  # Depart
  def depart
    @itin = Itinerary.find_by_id(params[:id])
    if @itin
      @itin.status_code = Itinerary::STATUS_IN_PROGRESS
      @itin.departure_time = tapped_at
      @itin.save(validate: false)
      StopTap.record(@itin, 'depart', params)
    end

    render success_response({})
  end

  # Arrive
  def arrive
    @itin = Itinerary.find_by_id(params[:id])
    if @itin
      @itin.arrival_time = tapped_at
      @itin.save(validate: false)
      StopTap.record(@itin, 'arrive', params)
    end

    render success_response({})
  end

  def pickup
    @itin = Itinerary.find_by_id(params[:id])
    if @itin
      @itin.status_code = Itinerary::STATUS_COMPLETED
      @itin.finish_time = tapped_at
      @itin.save(validate: false)
      StopTap.record(@itin, 'pickup', params)
    end

    render success_response({})
  end

  def dropoff
    @itin = Itinerary.find_by_id(params[:id])
    if @itin
      @itin.status_code = Itinerary::STATUS_COMPLETED
      @itin.finish_time = tapped_at
      @itin.save(validate: false)
      StopTap.record(@itin, 'dropoff', params)

      trip = @itin.trip
      if trip
        trip.trip_result = TripResult.find_by_code('COMP')
        trip.save(validate: false)
      end
    end

    render success_response({})
  end

  def noshow
    @itin = Itinerary.find_by_id(params[:id])
    # a queued tap sent again (the first answer was lost): dispatch was told already
    already = @itin && @itin.finish_time && @itin.trip&.trip_result&.code == 'NS'
    if @itin && !already
      @itin.status_code = Itinerary::STATUS_OTHER
      @itin.finish_time = tapped_at
      @itin.save(validate: false)
      StopTap.record(@itin, 'noshow', params)

      trip = @itin.trip
      if trip
        trip.trip_result = TripResult.find_by_code('NS')
        trip.save(validate: false)
        tell_dispatch_no_show(trip)
      end
    end

    render success_response({})
  end

  # When the driver tapped. The app (1.0.30+) sends `at` with every stop tap, and
  # a tap made with no connection is saved on the tablet and sent later: record
  # when it happened, not when it arrived. Only a plausible time is taken.
  def tapped_at
    t = params[:at].present? && (Time.zone.parse(params[:at].to_s) rescue nil)
    t && t > 36.hours.ago && t < 2.minutes.from_now ? t : DateTime.current
  end
  private :tapped_at

  def undo
    @itin = Itinerary.find_by_id(params[:id])
    if @itin
      fare = @itin.fare
      trip = @itin.trip

      if fare && trip && @itin.is_pickup? && @itin.finish_time && trip.fare_collected_time
        FareTap.new(provider: trip.provider, driver: @driver).refund_trip!(trip)   # a card payment goes back on the card
        trip.fare_collected_time = nil
      elsif fare && @itin.is_pickup? && @itin.finish_time && !trip.fare_collected_time
        @itin.finish_time = nil
        @itin.status_code = Itinerary::STATUS_IN_PROGRESS
        revert_trip_result = true
      elsif fare && @itin.is_dropoff? && !@itin.finish_time && trip.fare_collected_time
        FareTap.new(provider: trip.provider, driver: @driver).refund_trip!(trip)
        trip.fare_collected_time = nil
      elsif fare && @itin.is_dropoff? && !@itin.finish_time && @itin.arrival_time && !trip.fare_collected_time
        @itin.arrival_time = nil
      else
        if @itin.finish_time
          @itin.finish_time = nil
          @itin.status_code = Itinerary::STATUS_IN_PROGRESS
          revert_trip_result = true
        else
          if @itin.arrival_time
            @itin.arrival_time = nil
          elsif @itin.departure_time
            @itin.departure_time = nil
            @itin.status_code = Itinerary::STATUS_PENDING
          end
        end
      end

      @itin.save(validate: false) if @itin.changed?

      if trip
        trip.trip_result = nil if revert_trip_result
        trip.save(validate: false) if trip.changed?
      end
    end

    render success_response({})
  end

  def update_eta
    EtaUpdateWorker.perform_async(params[:id], params[:eta])
    render success_response({})
  end

  private

  # A driver marking a no-show tells the dispatch desk (pop-up and chime),
  # as a message from the driver about that rider. No approval needed
  # (Philz, 2026-10-01: operators mark no-shows themselves).
  def tell_dispatch_no_show(trip)
    return unless @driver && @itin.run
    who = trip.customer.try(:name) || "Rider"
    where = @itin.address.try(:one_line_text)
    RoutineMessage.create(provider_id: @itin.run.provider_id, driver: @driver, run: @itin.run, trip: trip, sender: current_user,
                          body: "No-show: #{who}#{where.present? ? " at #{where}" : ''} (#{Time.zone.now.strftime('%-l:%M %p')})")
  rescue StandardError => e
    Rails.logger.warn("no-show message for trip #{trip.id} failed: #{e.class}: #{e.message}")
  end

  # The stop is gone from the run: dispatch unscheduled or cancelled the trip
  # and republished while the tablet still had the old manifest open. A 404,
  # not a 500 in the error log; the tablet already treats a failed load as
  # nothing to show.
  def render_itinerary_gone
    render fail_response(status: 404, code: "itinerary_removed", itinerary: "This stop is no longer on your run.")
  end

  def itin_params
    params.require(:itinerary).permit(:status_code, :departure_time, :arrival_time, :finish_time)
  end
end
