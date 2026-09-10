require "rails_helper"

RSpec.describe FareTap do
  let(:provider) { create(:provider) }
  let!(:setup)   { build_fixed_run(provider) }
  let(:run)      { setup[0] }
  let(:driver)   { setup[1] }
  let(:route)    { setup[2] }
  let(:rider)    { create_rider(provider) }
  let(:token)    { FareToken.create!(provider: provider, customer: rider, kind: "rfid", uid: "04A3B2C1") }
  let(:tap)      { FareTap.new(provider: provider, driver: driver) }
  let(:adult)    { RiderCategory.find_by(name: "Adult") }
  let(:senior)   { RiderCategory.find_by(name: "Senior") }

  def tap!(**opts)
    tap.fixed_route!(**{ run: run, uid: token.uid, client_uuid: SecureRandom.uuid, stop: route.stops.first }.merge(opts))
  end

  before { FareLedger.new(rider, provider: provider).load!(10, payment_method: "cash") }

  it "records a walk-on for the rider and debits the category fare" do
    r = tap!
    expect(r.fare).to eq 1.0
    expect(r.balance).to eq 9.0
    expect(r.customer).to eq rider
    b = r.rows.first
    expect(b.customer).to eq rider
    expect(b.fare_token).to eq token
    expect(b.boarded_count).to eq 1
    expect(b.fare_type.name).to eq "Card"
    expect(b.stop_name).to eq "Depot"
    expect(b.fare_transaction).to eq r.transaction
    expect(r.transaction.run).to eq run
    expect(r.transaction.driver).to eq driver
  end

  it "uses the rider's own category" do
    rider.update!(default_rider_category_id: senior.id)
    expect(tap!.fare).to eq 0.5
  end

  it "ignores a double tap on the same run" do
    first = tap!
    again = tap!(recorded_at: first.rows.first.recorded_at + 30.seconds)
    expect(again.double_tap).to be true
    expect(again.rows).to be_empty
    expect(rider.reload.fare_balance).to eq 9.0
  end

  it "makes a different route inside the transfer window free, but not the same route, and not after the window" do
    t0 = Time.current
    tap!(recorded_at: t0)
    pink = FixedRoute.create!(provider: provider, name: "Pink", color: "FF69B4")
    pink_run = create(:run, provider: provider, driver: driver, vehicle: run.vehicle, service_mode: "fixed_route", fixed_route_id: pink.id)
    r = tap.fixed_route!(run: pink_run, uid: token.uid, client_uuid: SecureRandom.uuid, recorded_at: t0 + 30.minutes)
    expect(r.transfer).to be true
    expect(r.fare).to eq 0
    expect(r.rows.first.fare_type.name).to eq "Free / Transfer"
    expect(rider.reload.fare_balance).to eq 9.0
    # back onto Red (same route as the first tap) 20 minutes later: a ride home, charged
    red_again = create(:run, provider: provider, driver: driver, vehicle: run.vehicle, service_mode: "fixed_route", fixed_route_id: route.id)
    home = tap.fixed_route!(run: red_again, uid: token.uid, client_uuid: SecureRandom.uuid, recorded_at: t0 + 50.minutes)
    expect(home.transfer).to be false
    expect(rider.reload.fare_balance).to eq 8.0
    late = tap.fixed_route!(run: pink_run, uid: token.uid, client_uuid: SecureRandom.uuid, recorded_at: t0 + 4.hours)
    expect(late.transfer).to be false
    expect(rider.reload.fare_balance).to eq 7.0
  end

  it "lets the same route transfer when the provider allows it" do
    provider.update!(fare_transfer_different_route_only: false)
    t0 = Time.current
    tap!(recorded_at: t0)
    red_again = create(:run, provider: provider, driver: driver, vehicle: run.vehicle, service_mode: "fixed_route", fixed_route_id: route.id)
    r = tap.fixed_route!(run: red_again, uid: token.uid, client_uuid: SecureRandom.uuid, recorded_at: t0 + 30.minutes)
    expect(r.transfer).to be true
    expect(rider.reload.fare_balance).to eq 9.0
  end

  it "does not charge a rider with a valid pass" do
    rider.update!(fare_pass_expires_on: Date.current + 10)
    r = tap!
    expect(r.pass).to be true
    expect(r.fare).to eq 0
    expect(r.rows.first.fare_type.name).to eq "Pass"
    expect(rider.reload.fare_balance).to eq 10.0
  end

  it "refuses a tap that would go under the floor, and records it if it already happened offline" do
    rider.update!(fare_balance_floor: 0)
    FareLedger.new(rider, provider: provider).adjust!(-9.5, note: "test")
    expect { tap! }.to raise_error(FareTap::BelowFloor) { |e| expect(e.balance).to eq 0.5; expect(e.fare).to eq 1.0 }
    expect(run.fixed_route_boardings.count).to eq 0
    r = tap!(offline: true)
    expect(r.balance).to eq(-0.5)
    expect(run.fixed_route_boardings.count).to eq 1
  end

  it "answers a retried client_uuid as a duplicate without charging again" do
    uuid = SecureRandom.uuid
    tap!(client_uuid: uuid)
    r = tap!(client_uuid: uuid)
    expect(r.duplicate).to be true
    expect(rider.reload.fare_balance).to eq 9.0
  end

  it "refuses unknown, blocked and inactive" do
    expect { tap!(uid: "DEADBEEF") }.to raise_error(FareTap::UnknownToken)
    token.update!(status: "blocked")
    expect { tap! }.to raise_error(FareTap::TokenNotUsable, /blocked/)
    token.update!(status: "active")
    rider.update_column(:active, false)
    expect { tap! }.to raise_error(FareTap::TokenNotUsable, /inactive/)
  end

  it "refunds when the walk-on is undone" do
    r = tap!
    r.rows.each(&:destroy)
    tap.refund_boarding!(r.rows)
    expect(rider.reload.fare_balance).to eq 10.0
    tap.refund_boarding!(r.rows)   # idempotent
    expect(rider.reload.fare_balance).to eq 10.0
  end
end
