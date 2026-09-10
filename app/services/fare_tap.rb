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
#   - a debit inside the provider's transfer window: boarding recorded as a transfer, no charge
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
    transfer = !pass && last_tap && last_tap.recorded_at > recorded_at - provider.fare_transfer_window_minutes.minutes
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

  # The rider's most recent fare-card boarding, for double-tap and transfer checks.
  def last_fixed_route_tap(customer)
    FixedRouteBoarding.where(customer_id: customer.id, provider_id: provider.id).order(recorded_at: :desc, id: :desc).first
  end
end
