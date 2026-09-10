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
