# The only way to change a rider's fare balance. Every posting takes the
# customer's row lock, writes one FareTransaction with the resulting
# balance_after, and stores that balance on the customer. client_uuid makes a
# retried posting (an offline tablet resending a tap) return the row that
# already landed instead of posting twice.
#
#   FareLedger.new(customer, by: current_user).load!(10, payment_method: "cash")
#   FareLedger.new(customer, by: current_user).debit!(1.50, token: token, run: run)
#
# Amounts are given as positive numbers; the ledger applies the sign.
class FareLedger
  class Error < StandardError; end
  class BelowFloor < Error
    attr_reader :balance, :floor
    def initialize(balance, floor)
      @balance, @floor = balance, floor
      super("Balance would be #{'%.2f' % balance}, below the allowed #{'%.2f' % floor}")
    end
  end

  attr_reader :customer, :provider

  def initialize(customer, by: nil, provider: nil)
    @customer = customer
    @provider = provider || customer.provider
    @by = by
  end

  def load!(amount, payment_method:, reference: nil, note: nil, token: nil, client_uuid: nil, recorded_at: nil, tendered: nil)
    post!(kind: "load", amount: money(amount).abs, payment_method: payment_method, reference: reference,
          note: note, fare_token: token, client_uuid: client_uuid, recorded_at: recorded_at,
          tendered: (tendered.nil? ? nil : money(tendered)))
  end

  # A 10- or 20-trip pass is stored value: trips x the rider's category fare
  # goes on the card; the cash taken may be less if the provider discounts.
  def sell_trip_pass!(trips:, fare_each:, payment_method:, reference: nil, category_name: nil, discount_pct: 0, client_uuid: nil)
    value = (money(fare_each) * trips).round(2)
    raise Error, "This rider's category fare is $0.00; nothing to sell." if value <= 0
    price = (value * (100 - discount_pct.to_i) / 100).round(2)
    load!(value, payment_method: payment_method, reference: reference, client_uuid: client_uuid,
          tendered: (price == value ? nil : price),
          note: "#{trips}-ride pass#{category_name ? " (#{category_name} @ #{'%.2f' % fare_each})" : ''}#{price == value ? '' : ", paid #{'%.2f' % price}"}")
  end

  # A monthly pass: the price is loaded and debited in one go, so the ledger
  # carries the money and the balance is unchanged; the pass itself is the
  # expiry date on the customer.
  def sell_monthly_pass!(price:, through:, payment_method:, reference: nil, client_uuid: nil)
    price = money(price)
    raise Error, "No monthly pass price is set for this provider." if price <= 0
    uuid = client_uuid || SecureRandom.uuid
    FareTransaction.transaction do
      label = "Monthly pass (unlimited) through #{through.strftime('%m/%d/%Y')}"
      load!(price, payment_method: payment_method, reference: reference, client_uuid: "#{uuid}-load", note: label)
      tx = post!(kind: "pass", amount: -price, client_uuid: "#{uuid}-pass", note: label)
      customer.update_columns(fare_pass_expires_on: through)
      tx
    end
  end

  def refund!(amount, note:, reference: nil, client_uuid: nil, recorded_at: nil)
    post!(kind: "refund", amount: money(amount).abs, note: note, reference: reference,
          client_uuid: client_uuid, recorded_at: recorded_at)
  end

  # Signed. The note is required: an adjustment is a correction and the
  # ledger should say what it corrects.
  def adjust!(amount, note:, client_uuid: nil, recorded_at: nil)
    post!(kind: "adjust", amount: money(amount), note: note, client_uuid: client_uuid, recorded_at: recorded_at)
  end

  # A fare taken at the door. Refused below the floor unless allow_below_floor
  # (an offline tap that already happened is recorded regardless).
  def debit!(amount, token: nil, run: nil, trip: nil, boarding: nil, driver: nil, note: nil,
             client_uuid: nil, recorded_at: nil, allow_below_floor: false)
    post!(kind: "debit", amount: -money(amount).abs, fare_token: token, run: run, trip: trip,
          fixed_route_boarding: boarding, driver: driver, note: note, client_uuid: client_uuid,
          recorded_at: recorded_at, allow_below_floor: allow_below_floor)
  end

  # Move a balance to another rider (a replacement account, a family member).
  def transfer!(amount, to:, note: nil)
    amount = money(amount).abs
    uuid = SecureRandom.uuid
    FareTransaction.transaction do
      out = post!(kind: "transfer_out", amount: -amount, note: note, client_uuid: "#{uuid}-out", allow_below_floor: false)
      self.class.new(to, by: @by, provider: provider).post!(kind: "transfer_in", amount: amount, note: note, client_uuid: "#{uuid}-in")
      out
    end
  end

  def floor
    customer.fare_balance_floor || provider.try(:fare_negative_floor) || 0
  end

  protected

  def post!(kind:, amount:, client_uuid: nil, recorded_at: nil, allow_below_floor: true, **attrs)
    client_uuid ||= SecureRandom.uuid
    if (existing = FareTransaction.find_by(client_uuid: client_uuid))
      return existing
    end
    raise Error, "Amount must not be zero" if amount.zero?

    Customer.transaction do
      customer.lock!
      new_balance = money(customer.fare_balance) + amount
      if amount < 0 && !allow_below_floor && new_balance < money(floor)
        raise BelowFloor.new(new_balance, floor)
      end
      tx = FareTransaction.create!(
        attrs.merge(
          provider: provider, customer: customer, kind: kind, amount: amount, balance_after: new_balance,
          recorded_by: @by, client_uuid: client_uuid, recorded_at: recorded_at || Time.current
        )
      )
      customer.update_column(:fare_balance, new_balance)
      tx
    end
  rescue ActiveRecord::RecordNotUnique
    FareTransaction.find_by!(client_uuid: client_uuid)
  end

  private

  def money(n)
    BigDecimal(n.to_s).round(2)
  end
end
