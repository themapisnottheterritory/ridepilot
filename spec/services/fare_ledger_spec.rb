require "rails_helper"

RSpec.describe FareLedger do
  let(:provider) { create(:provider) }
  let(:rider)    { create_rider(provider) }
  let(:ledger)   { FareLedger.new(rider, provider: provider) }

  it "posts a load and caches the balance on the rider" do
    tx = ledger.load!(10, payment_method: "cash")
    expect(tx.kind).to eq "load"
    expect(tx.amount).to eq 10
    expect(tx.balance_after).to eq 10
    expect(rider.reload.fare_balance).to eq 10
  end

  it "takes a fare and keeps balance_after right across postings" do
    ledger.load!(10, payment_method: "cash")
    tx = ledger.debit!(1.5)
    expect(tx.amount).to eq(-1.5)
    expect(tx.balance_after).to eq 8.5
    ledger.debit!("1.50")
    expect(rider.reload.fare_balance).to eq 7
    expect(rider.fare_transactions.chronological.map(&:balance_after)).to eq [10, 8.5, 7]
  end

  it "refuses a fare that would go below the floor" do
    ledger.load!(1, payment_method: "cash")
    expect { ledger.debit!(1.5) }.to raise_error(FareLedger::BelowFloor)
    expect(rider.reload.fare_balance).to eq 1
    expect(rider.fare_transactions.count).to eq 1
  end

  it "honours the provider floor and a per-rider override" do
    provider.update!(fare_negative_floor: -5)
    ledger.debit!(1.5)
    expect(rider.reload.fare_balance).to eq(-1.5)
    rider.update!(fare_balance_floor: -2)
    expect { ledger.debit!(1.5) }.to raise_error(FareLedger::BelowFloor)
  end

  it "records an offline tap below the floor when told to" do
    tx = ledger.debit!(1.5, allow_below_floor: true)
    expect(tx.balance_after).to eq(-1.5)
  end

  it "is idempotent on client_uuid" do
    a = ledger.load!(10, payment_method: "cash", client_uuid: "abc")
    b = ledger.load!(10, payment_method: "cash", client_uuid: "abc")
    expect(b).to eq a
    expect(rider.reload.fare_balance).to eq 10
  end

  it "requires a reason on an adjustment and a method on a load" do
    expect { ledger.adjust!(-2, note: nil) }.to raise_error(ActiveRecord::RecordInvalid)
    expect { ledger.load!(5, payment_method: "gold") }.to raise_error(ActiveRecord::RecordInvalid)
    expect(rider.reload.fare_balance).to eq 0
  end

  it "never lets a posted row change" do
    tx = ledger.load!(10, payment_method: "cash")
    expect { tx.update!(amount: 99) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { tx.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it "moves a balance to another rider" do
    other = create_rider(provider)
    ledger.load!(10, payment_method: "check", reference: "1234")
    ledger.transfer!(4, to: other, note: "replacement account")
    expect(rider.reload.fare_balance).to eq 6
    expect(other.reload.fare_balance).to eq 4
    expect(other.fare_transactions.last.kind).to eq "transfer_in"
  end
end

RSpec.describe FareLedger, "pass sales" do
  let(:provider) { create(:provider) }
  let(:rider)    { create_rider(provider) }
  let(:ledger)   { FareLedger.new(rider, provider: provider) }

  it "sells a 10-trip pass as stored value at the rider's fare" do
    tx = ledger.sell_trip_pass!(trips: 10, fare_each: 0.50, category_name: "Senior 60+", payment_method: "cash")
    expect(tx.amount).to eq 5.0
    expect(tx.tendered).to be_nil
    expect(tx.cash_in).to eq 5.0
    expect(tx.note).to eq "10-trip pass (Senior 60+ @ 0.50)"
    expect(rider.reload.fare_balance).to eq 5.0
  end

  it "credits the full value but records the discounted cash" do
    tx = ledger.sell_trip_pass!(trips: 20, fare_each: 1.00, payment_method: "check", reference: "9", discount_pct: 10)
    expect(tx.amount).to eq 20.0
    expect(tx.tendered).to eq 18.0
    expect(tx.cash_in).to eq 18.0
    expect(tx.note).to include("paid 18.00")
    expect(rider.reload.fare_balance).to eq 20.0
  end

  it "refuses a trip pass for a $0 fare" do
    expect { ledger.sell_trip_pass!(trips: 10, fare_each: 0, payment_method: "cash") }.to raise_error(FareLedger::Error)
  end

  it "sells a monthly pass: money on the ledger, balance unchanged, expiry set" do
    ledger.load!(3, payment_method: "cash")
    through = Date.current.next_month.end_of_month
    tx = ledger.sell_monthly_pass!(price: 30, through: through, payment_method: "cash")
    expect(tx.kind).to eq "pass"
    expect(tx.amount).to eq(-30)
    expect(rider.reload.fare_balance).to eq 3.0
    expect(rider.fare_pass_expires_on).to eq through
    expect(rider.fare_pass_active?(through)).to be true
    expect(rider.fare_transactions.loads.sum(:amount)).to eq 33.0
    expect { ledger.sell_monthly_pass!(price: 0, through: through, payment_method: "cash") }.to raise_error(FareLedger::Error)
  end
end
