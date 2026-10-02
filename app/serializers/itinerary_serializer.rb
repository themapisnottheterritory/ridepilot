class ItinerarySerializer
  include FastJsonapi::ObjectSerializer
  set_type :itinerary

  belongs_to :address

  attribute :id, :trip_id, :run_id, :leg_flag, :status_code, :departure_time, :arrival_time, :finish_time, :eta, :time   # run_id: the app keeps taps per run (1.0.30)

  # an older stop with no status is Pending to the tablet, which offers Depart only then
  attribute :status_code do |object|
    object.status_code || Itinerary::STATUS_PENDING
  end

  attribute :eta do |object|
    if object.public_itinerary
      object.public_itinerary.eta
    else
      object.eta
    end
  end

  attribute :time_seconds do |object|
    (object.time - object.time.beginning_of_day).to_i if object.time
  end

  attribute :eta_seconds do |object|
    if object.public_itinerary
      eta = object.public_itinerary.eta
    else
      eta = object.eta
    end

    (eta - eta.beginning_of_day).to_i if eta
  end

  attribute :processing_time_seconds do |object|
    if object.trip
      object.is_pickup? ? (object.trip.passenger_load_min || 0) * 60 : (object.trip.passenger_unload_min || 0) * 60
    end
  end

  attribute :early_pickup_not_allowed do |object|
    true if object.trip && object.is_pickup? && !object.trip.early_pickup_allowed
  end

  WILL_CALL_NOTE = "WILL CALL: the rider calls when ready. The time is an estimate; check with dispatch before heading there.".freeze

  # a will-call pickup says so first, and a pickup whose funding source pays
  # the whole ride says NO FARE, so drivers see both on the app they have
  attribute :trip_notes do |object|
    if object.trip
      pickup = object.is_pickup?
      lines = []
      lines << WILL_CALL_NOTE if object.trip.will_call && pickup
      lines << object.trip.funding_source&.driver_note if pickup
      lines << object.trip.notes.presence
      lines.compact.join("\n").presence
    end
  end

  attribute :will_call do |object|
    !!(object.trip&.will_call && object.is_pickup?)
  end

  attribute :customer_notes do |object|
    object.trip.customer.try(:public_notes) if object.trip
  end

  attribute :trip_result do |object|
    object.trip.trip_result.try(:name) if object.trip
  end

  attribute :trip_address_notes do |object|
    if object.trip
      if object.is_pickup?
        object.trip.pickup_address_notes
      else
        object.trip.dropoff_address_notes
      end
    end
  end

  attribute :mobility_notes do |object|
    if object.trip && object.is_pickup?
      object.trip.mobility_notes
    end
  end

  attribute :funding_source do |object|
    if object.trip
      object.trip.funding_source.try(:name)
    end
  end

  attribute :customer_name do |object|
    object.trip.customer.name if object.trip
  end

  attribute :phone do |object|
    object.trip.customer.phone_number_1 || object.trip.customer.phone_number_1 if object.trip && object.trip.customer
  end

  # no fare box on a trip whose funding source pays the whole ride
  attribute :fare do |object|
    fare = object.fare
    fare = nil if object.trip&.funding_source&.no_fare?
    if fare
      trip = object.trip
      collected_time = trip.fare_collected_time
      if fare.is_payment?
        fare_amount = trip.fare_amount
      else
        fare_amount = trip.donation.try(:amount)
      end

      customer = trip.customer
      {
        fare_type: fare.fare_type,
        pre_trip: fare.pre_trip,
        amount: fare_amount,
        collected_time: collected_time,
        # Fare cards: what to prefill, whether to expect a tap, and whether the card already paid.
        default_amount: (trip.fare_amount.to_f > 0 ? trip.fare_amount.to_f : (trip.provider && (FareSchedule.new(trip.provider).trip_fare(trip)&.to_f || trip.provider.fare_udr_default.to_f))),
        card_on_file: (customer ? customer.fare_tokens.active.exists? : false),
        card_balance: customer&.fare_balance&.to_f,
        paid_by_card: FareTransaction.where(trip_id: trip.id, kind: "debit").exists?
      }
    end
  end

  attribute :return_trip_time do |object|
    trip = object.trip
    if trip && trip.is_outbound? && trip.return_trip && !trip.return_trip.is_cancelled_or_turned_down?
      trip.return_trip.pickup_time
    end
  end
end
