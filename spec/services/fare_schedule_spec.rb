require "rails_helper"

RSpec.describe FareSchedule do
  let(:provider) { create(:provider) }
  let(:adult)    { RiderCategory.find_or_create_by!(name: "Adult") { |c| c.default_fare = 1.00 } }
  let(:senior)   { RiderCategory.find_or_create_by!(name: "Senior 60+") { |c| c.default_fare = 0.50 } }
  let(:child)    { RiderCategory.find_or_create_by!(name: "Youth 0-5") { |c| c.default_fare = 0 } }
  let(:schedule) { FareSchedule.new(provider) }

  def seed!
    schedule.replace!({
      "5"  => { adult.id => "1.00", senior.id => "0.50", child.id => "" },
      "10" => { adult.id => "2.00", senior.id => "1.00", child.id => "0" },
      ""   => { adult.id => "5.00", senior.id => "2.50", child.id => "0" }
    })
  end

  it "is unconfigured until rows exist" do
    expect(schedule.configured?).to be false
    expect(schedule.price(miles: 3, category: adult)).to be_nil
  end

  it "prices by band edge: up to and including the edge, then the next band, then open-ended" do
    seed!
    expect(schedule.price(miles: 0.4, category: adult)).to eq 1.00
    expect(schedule.price(miles: 5.0, category: adult)).to eq 1.00
    expect(schedule.price(miles: 5.1, category: adult)).to eq 2.00
    expect(schedule.price(miles: 10, category: senior)).to eq 1.00
    expect(schedule.price(miles: 47, category: senior)).to eq 2.50
    expect(schedule.price(miles: 47, category: child)).to eq 0
    expect(schedule.bands).to eq [5, 10, nil]
  end

  it "prices a trip as rider plus one adult fare per guest, attendants free" do
    seed!
    rider = create_rider(provider, default_rider_category_id: senior.id)
    trip, = build_udr_trip(provider, rider)
    trip.update_columns(drive_distance: 7.2, guest_count: 2, attendant_count: 1)
    expect(schedule.trip_fare(trip)).to eq 1.00 + 2 * 2.00
    trip.update_columns(guest_count: 0)
    expect(schedule.trip_fare(trip)).to eq 1.00
    trip.update_columns(drive_distance: nil)
    expect(schedule.trip_fare(trip)).to be_nil
  end

  it "replaces the whole table on save and audits it" do
    seed!
    schedule.replace!({ "8" => { adult.id => "1.50" } })
    expect(FareScheduleRow.for_provider(provider.id).count).to eq 1
    expect(schedule.price(miles: 7, category: adult)).to eq 1.50
    expect(schedule.price(miles: 9, category: adult)).to be_nil
  end
end

RSpec.describe FareTap, "#trip! with a schedule" do
  let(:provider) { create(:provider) }
  let(:senior)   { RiderCategory.find_or_create_by!(name: "Senior 60+") { |c| c.default_fare = 0.50 } }
  let(:adult)    { RiderCategory.find_or_create_by!(name: "Adult") { |c| c.default_fare = 1.00 } }
  let(:rider)    { create_rider(provider, default_rider_category_id: senior.id) }
  let!(:setup)   { build_udr_trip(provider, rider) }
  let(:trip)     { setup[0] }
  let(:token)    { FareToken.create!(provider: provider, customer: rider, kind: "rfid", uid: "04A3B2C1") }

  before do
    provider.update!(fare_udr_default: 9.99)
    FareLedger.new(rider, provider: provider).load!(20, payment_method: "cash")
    FareSchedule.new(provider).replace!({ "5" => { adult.id => "1.00", senior.id => "0.50" }, "" => { adult.id => "2.00", senior.id => "1.00" } })
  end

  it "charges the scheduled fare for the trip's distance ahead of the flat default" do
    trip.update_columns(drive_distance: 12.0, guest_count: 1)
    r = FareTap.new(provider: provider, driver: setup[2]).trip!(trip: trip, uid: token.uid, client_uuid: SecureRandom.uuid)
    expect(r.fare).to eq 1.00 + 2.00
    expect(rider.reload.fare_balance).to eq 17.0
  end

  it "falls back to the flat default when the trip has no distance" do
    trip.update_columns(drive_distance: nil)
    r = FareTap.new(provider: provider, driver: setup[2]).trip!(trip: trip, uid: token.uid, client_uuid: SecureRandom.uuid)
    expect(r.fare).to eq 9.99
  end
end

RSpec.describe ProvidersController, "update_fare_schedule", type: :controller do
  login_admin_as_current_user

  it "saves the grid from the provider page" do
    provider = @current_user.current_provider
    adult = RiderCategory.find_or_create_by!(name: "Adult") { |c| c.default_fare = 1.00 }
    post :update_fare_schedule, params: { id: provider.id, service: "demand_response", schedule: {
      "0" => { edge: "5", fares: { adult.id.to_s => "1.00" }, remove: "0" },
      "1" => { edge: "10", fares: { adult.id.to_s => "2.00" }, remove: "1" },
      "2" => { edge: "", fares: { adult.id.to_s => "$3.00" }, remove: "0" }
    } }
    expect(response).to redirect_to(general_provider_path(provider, anchor: "fare_schedule"))
    s = FareSchedule.new(provider)
    expect(s.bands).to eq [5, nil]
    expect(s.price(miles: 30, category: adult)).to eq 3.00
  end
end
