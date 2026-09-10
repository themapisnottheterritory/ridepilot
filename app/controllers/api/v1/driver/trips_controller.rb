class Api::V1::Driver::TripsController < Api::V1::Driver::BaseController

  def update_fare
    @trip = Trip.find_by_id(params[:id])
    fare = @trip.fare || @trip.provider.fare.try(:dup)
    if fare && !fare.is_free?
      @trip.fare_collected_time = DateTime.now
      if fare.is_payment?
        @trip.fare_amount = params[:fare_amount]
        @trip.save(validate: false)
      else
        donation = @trip.donation || @trip.build_donation
        donation.customer = @trip.customer
        donation.user = current_user
        donation.amount = params[:fare_amount]
        donation.date = DateTime.now
        donation.save(validate: false) if donation.amount && donation.amount > 0
      end

      @trip.fare = fare
      @trip.save(validate: false) if @trip.changed?
    end

    render success_response({})
  end

  # Fare card at a demand-response pickup (docs/fare-card-design.md, 5.2).
  #
  #   POST   /api/v1/trips/:id/token_tap   { uid, client_uuid, recorded_at?, amount?, confirm_mismatch? }
  #   DELETE /api/v1/trips/:id/token_tap   refund the card payment and clear the collected mark
  #
  # 409 with both names when the card is not the booked rider's; the tablet
  # asks the driver and resends with confirm_mismatch: true.
  def token_tap
    trip = driver_trip or return
    uuid = params[:client_uuid].to_s.strip
    return render fail_response(status: 422, client_uuid: "client_uuid is required.") if uuid.blank?
    uid = params[:uid].to_s.strip
    return render fail_response(status: 422, uid: "Nothing was read from the card.") if uid.blank?
    recorded_at = (Time.zone.parse(params[:recorded_at].to_s) rescue nil) || Time.current

    result = FareTap.new(provider: trip.provider, driver: @driver).trip!(
      trip: trip, uid: uid, client_uuid: uuid, recorded_at: recorded_at, amount: params[:amount].presence,
      confirm_mismatch: ActiveModel::Type::Boolean.new.cast(params[:confirm_mismatch]) || false,
      offline: ActiveModel::Type::Boolean.new.cast(params[:offline]) || false
    )
    render success_response({
      tap: { rider_name: result.customer&.name, fare: result.fare.to_f, balance: result.balance.to_f,
             pass: !!result.pass, duplicate: !!result.duplicate,
             paid_for: (trip.customer_id != result.customer&.id ? trip.customer&.name : nil),
             collected_at: trip.reload.fare_collected_time }
    })
  rescue FareTap::Mismatch => e
    render fail_response(status: 409, code: "mismatch", tap: e.message, card_rider_name: e.token.customer.name, trip_rider_name: trip.customer&.name)
  rescue FareTap::UnknownToken => e
    render fail_response(status: 404, code: "unknown_token", uid: FareToken.normalize_uid(uid), tap: e.message)
  rescue FareTap::TokenNotUsable => e
    render fail_response(status: 422, code: "token_not_usable", tap: e.message, rider_name: e.token.customer&.name)
  rescue FareTap::BelowFloor => e
    render fail_response(status: 422, code: "below_floor", tap: e.message, rider_name: e.customer.name, balance: e.balance.to_f, fare: e.fare.to_f)
  rescue FareTap::AlreadyCollected => e
    render fail_response(status: 422, code: "already_collected", tap: e.message)
  rescue FareTap::Error => e
    render fail_response(status: 422, code: "tap_failed", tap: e.message)
  end

  def undo_token_tap
    trip = driver_trip or return
    refund = FareTap.new(provider: trip.provider, driver: @driver).refund_trip!(trip)
    return render fail_response(status: 404, tap: "No card payment on this trip.") unless refund
    render success_response({ refunded: refund.amount.to_f, balance: refund.balance_after.to_f })
  end

  private

  # The trip must be on one of this driver's runs.
  def driver_trip
    trip = Trip.joins(:run).where(id: params[:id], runs: { driver_id: @driver.id }).first
    render fail_response(status: 404, trip: "Trip not found on your runs.") unless trip
    trip
  end
end
