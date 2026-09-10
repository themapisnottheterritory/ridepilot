# A rider presents a fare token at the door. This resolves the token, works
# out what the ride costs them, writes the boarding and the ledger debit in
# one transaction, and answers with what the tablet should show.
#
#   FareTap.new(provider: run.provider, driver: driver).fixed_route!(run: run, uid: "04A3B2C1", client_uuid: ..., ...)
#
# Errors are typed so the API can map them to a red screen with a reason.
# The rule set (docs/fare-card-design.md, section 5.1):
#   - unknown / blocked / lost token, or an inactive rider: refused
#   - a second tap on the same run inside DOUBLE_TAP_SECONDS: ignored (no charge, no row)
#   - a valid pass: boarding recorded with the Pass fare type, no charge
#   - an earlier tap inside the provider's transfer window, on a different route when the
#     provider says so: boarding recorded as a transfer, no charge
#   - otherwise: fare = rider category default fare x Card fare type factor, debited
#   - a debit that would go under the floor is refused, unless the tap already
#     happened offline (offline: true), in which case it is recorded anyway.
class FareTap
  class Error < StandardError
    def code; self.class.name.demodulize.underscore; end
  end
  class UnknownToken  < Error; end
  class TokenNotUsable < Error
    attr_reader :token
    def initialize(token, msg); @token = token; super(msg); end
  end
  class Mismatch < Error
    attr_reader :token, :trip
    def initialize(token, trip)
      @token, @trip = token, trip
      super("This card belongs to #{token.customer.name}, not #{trip.customer&.name || 'the booked rider'}.")
    end
  end
  class AlreadyCollected < Error; end
  class BelowFloor < Error
    attr_reader :balance, :fare, :customer
    def initialize(customer, balance, fare)
      @customer, @balance, @fare = customer, balance, fare
      super("Balance #{'%.2f' % balance} is not enough for a #{'%.2f' % fare} fare")
    end
  end

  DOUBLE_TAP_SECONDS = 120

  Result = Struct.new(:customer, :token, :category, :fare_type, :fare, :transaction, :rows,
                      :transfer, :pass, :double_tap, :duplicate, keyword_init: true) do
    def balance
      transaction ? transaction.balance_after : customer.fare_balance
    end
  end

  attr_reader :provider, :driver

  def initialize(provider:, driver: nil, by: nil)
    @provider = provider
    @driver = driver
    @by = by
  end

  # What a reader typed -> a usable token, or a typed error.
  def resolve!(uid)
    token = FareToken.for_provider(provider.id).lookup(uid)
    # The driver may have typed the printed serial instead (reader down, QR sheet).
    token ||= FareToken.for_provider(provider.id).find_by(serial: uid.to_s.strip.sub(/\A#/, "")) if uid.to_s.strip.length <= 8
    raise UnknownToken, "Unknown card." unless token
    raise TokenNotUsable.new(token, "This card is marked #{token.status}.") unless token.active?
    customer = token.customer
    raise TokenNotUsable.new(token, "Rider record is inactive.") unless customer && customer.active
    token
  end

  def fixed_route!(run:, uid:, client_uuid:, recorded_at: nil, stop: nil, stop_name: nil, direction: nil,
                   latitude: nil, longitude: nil, offline: false)
    recorded_at ||= Time.current
    existing = run.fixed_route_boardings.where(client_uuid: client_uuid).to_a
    if existing.any?
      first = existing.min_by(&:id)
      return Result.new(customer: first.customer, token: first.fare_token, category: first.rider_category,
                        fare_type: first.fare_type, fare: first.fare_amount.to_d, rows: existing,
                        transaction: FareTransaction.find_by(client_uuid: client_uuid), duplicate: true)
    end

    token = resolve!(uid)
    customer = token.customer
    category = rider_category_for(customer)
    raise Error, "No rider categories are set up." unless category

    last_tap = last_fixed_route_tap(customer)
    if last_tap && last_tap.run_id == run.id && last_tap.recorded_at > recorded_at - DOUBLE_TAP_SECONDS
      return Result.new(customer: customer, token: token, category: category, fare: 0.to_d, rows: [],
                        double_tap: true, transaction: nil)
    end

    pass     = customer.fare_pass_active?(recorded_at.to_date)
    transfer = !pass && transfer_from_paid_tap?(customer, run, recorded_at)
    fare_type, fare =
      if pass         then [fare_type_named("Pass") || card_fare_type, 0.to_d]
      elsif transfer  then [fare_type_named("Free / Transfer", "Transfer") || card_fare_type, 0.to_d]
      else
        ft = card_fare_type
        [ft, (category.default_fare.to_d * (ft&.fare_factor || 1).to_d).round(2)]
      end

    ledger = FareLedger.new(customer, by: @by, provider: provider)
    rows = []
    tx = nil
    FixedRouteBoarding.transaction do
      PaperTrail.request(whodunnit: (@by&.id || driver&.user_id).to_s.presence) do
        rows << FixedRouteBoarding.create!(
          run: run, stop: stop, stop_name: stop&.name || stop_name.presence, direction: stop&.direction || direction.presence,
          rider_category_id: category.id, fare_type: fare_type, boarded_count: 1, alighted_count: 0,
          fare_amount: fare, recorded_at: recorded_at, latitude: latitude.presence, longitude: longitude.presence,
          client_uuid: client_uuid, customer: customer, fare_token: token
        )
      end
      if fare > 0
        begin
          tx = ledger.debit!(fare, token: token, run: run, boarding: rows.first, driver: driver,
                             client_uuid: client_uuid, recorded_at: recorded_at, allow_below_floor: offline)
        rescue FareLedger::BelowFloor => e
          raise BelowFloor.new(customer, customer.fare_balance, fare)
        end
      end
    end

    Result.new(customer: customer, token: token, category: category, fare_type: fare_type, fare: fare,
               transaction: tx, rows: rows, transfer: !!transfer, pass: pass, double_tap: false, duplicate: false)
  end

  # Demand response (section 5.2): the trip already knows the rider and the
  # fare, so the tap is a confirmation and a debit. Someone else's card pays
  # for the trip only when the driver confirms the mismatch. One tap covers
  # the whole trip fare, guests and attendants included. A valid pass makes it
  # free but still marks the fare collected.
  def trip!(trip:, uid:, client_uuid:, recorded_at: nil, amount: nil, confirm_mismatch: false, offline: false)
    recorded_at ||= Time.current
    if (existing = FareTransaction.find_by(client_uuid: client_uuid))
      return Result.new(customer: existing.customer, token: existing.fare_token, fare: existing.amount.abs,
                        transaction: existing, rows: [], duplicate: true)
    end
    raise AlreadyCollected, "Fare already collected for this trip." if trip.fare_collected_time.present?
    fare_setting = trip.fare || provider.fare
    raise Error, "This trip has no fare to collect." if fare_setting.nil? || fare_setting.is_free?
    raise Error, "This trip takes a donation, not a fare." if fare_setting.is_donation?

    token = resolve!(uid)
    customer = token.customer
    raise Mismatch.new(token, trip) if trip.customer_id != customer.id && !confirm_mismatch

    pass = customer.fare_pass_active?(recorded_at.to_date)
    fare = pass ? 0.to_d : trip_fare_amount(trip, customer, amount)
    raise Error, "No fare amount is set for this trip or provider." if !pass && fare <= 0

    tx = nil
    Trip.transaction do
      if fare > 0
        begin
          tx = FareLedger.new(customer, by: @by, provider: provider)
                         .debit!(fare, token: token, run: trip.run, trip: trip, driver: driver, client_uuid: client_uuid,
                                 recorded_at: recorded_at, allow_below_floor: offline,
                                 note: (trip.customer_id != customer.id ? "Paid for #{trip.customer&.name}" : nil))
        rescue FareLedger::BelowFloor
          raise BelowFloor.new(customer, customer.fare_balance, fare)
        end
      end
      trip.fare ||= fare_setting.dup
      trip.fare_amount = fare.to_f
      trip.fare_collected_time = recorded_at
      trip.save(validate: false)
    end

    Result.new(customer: customer, token: token, fare: fare, transaction: tx, rows: [], pass: pass,
               transfer: false, double_tap: false, duplicate: false)
  end

  # The pickup was undone, or the driver asked to void the card payment:
  # refund the trip's card debit and clear the collected mark. Idempotent.
  def refund_trip!(trip)
    tx = FareTransaction.where(trip_id: trip.id, kind: "debit").order(:id).last
    return nil unless tx
    refund = FareLedger.new(tx.customer, by: @by, provider: provider)
                       .refund!(tx.amount.abs, note: "Card payment undone on the bus", client_uuid: "#{tx.client_uuid}-undo", recorded_at: Time.current)
    trip.update_columns(fare_collected_time: nil) if trip.fare_collected_time.present?
    refund
  end

  # Undo a tapped walk-on: the boarding rows are voided by the caller; this
  # returns the money. Idempotent on the derived client_uuid.
  def refund_boarding!(rows)
    first = rows.min_by(&:id)
    tx = FareTransaction.find_by(fixed_route_boarding_id: rows.map(&:id), kind: "debit")
    return nil unless tx && first.customer
    FareLedger.new(first.customer, by: @by, provider: provider)
              .refund!(tx.amount.abs, note: "Tap undone on the bus", client_uuid: "#{first.client_uuid}-undo", recorded_at: Time.current)
  end

  private

  # Explicit amount from the driver, else what dispatch put on the trip, else
  # the distance-band schedule (rider plus guests), else the provider's flat
  # card fare for demand response, else the rider's category fare.
  def trip_fare_amount(trip, customer, amount)
    explicit = amount.to_s.strip.presence && (BigDecimal(amount.to_s.gsub(/[$,\s]/, "")) rescue nil)
    return explicit.round(2) if explicit && explicit > 0
    return trip.fare_amount.to_d.round(2) if trip.fare_amount.to_f > 0
    scheduled = FareSchedule.new(provider).trip_fare(trip, category: rider_category_for(customer))
    return scheduled if scheduled && scheduled > 0
    return provider.fare_udr_default.to_d if provider.fare_udr_default.to_f > 0
    rider_category_for(customer)&.default_fare.to_d || 0.to_d
  end

  def rider_category_for(customer)
    visible = RiderCategory.by_provider(provider)
    (customer.default_rider_category_id && visible.find_by(id: customer.default_rider_category_id)) || visible.default_order.first
  end

  def card_fare_type
    @card_fare_type ||= fare_type_named("Card")
  end

  def fare_type_named(*names)
    scope = FareType.by_provider(provider)
    names.each do |n|
      ft = scope.where("lower(name) = ?", n.downcase).first
      return ft if ft
    end
    nil
  end

  # The rider's most recent fare-card boarding, for the double-tap check.
  def last_fixed_route_tap(customer)
    FixedRouteBoarding.where(customer_id: customer.id, provider_id: provider.id).order(recorded_at: :desc, id: :desc).first
  end

  # One free transfer per paid fare: the rider paid on a bus inside the
  # window, this bus is a different route (when the provider says so), and
  # they have not already used a transfer on that fare. Chaining Red -> Pink
  # -> Red therefore pays on the way home.
  def transfer_from_paid_tap?(customer, run, recorded_at)
    window_start = recorded_at - provider.fare_transfer_window_minutes.minutes
    paid = FixedRouteBoarding.where(customer_id: customer.id, provider_id: provider.id)
                             .where("fare_amount > 0").where("recorded_at > ?", window_start)
                             .order(recorded_at: :desc, id: :desc).first
    return false unless paid
    return false if provider.fare_transfer_different_route_only && paid.fixed_route_id.present? && paid.fixed_route_id == run.fixed_route_id
    used = FixedRouteBoarding.where(customer_id: customer.id, provider_id: provider.id)
                             .where("recorded_at > ?", paid.recorded_at).where("fare_amount = 0 OR fare_amount IS NULL").exists?
    !used
  end
end
