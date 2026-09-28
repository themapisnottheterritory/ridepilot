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

RSpec.describe FareSchedule, "paratransit" do
  let(:provider) { create(:provider, fare_paratransit: 1.50, fare_urban_cities: "Victoria, Bloomington") }
  let(:adult)    { RiderCategory.find_or_create_by!(name: "Adult") { |c| c.default_fare = 1.00 } }
  let(:rider)    { create_rider(provider, ada_eligible: true, default_rider_category_id: adult.id) }
  let(:schedule) { FareSchedule.new(provider) }

  def trip_between(from_city, to_city, **attrs)
    trip, = build_udr_trip(provider, rider)
    trip.pickup_address.update_columns(city: from_city)
    trip.dropoff_address.update_columns(city: to_city)
    trip.update_columns(**{ drive_distance: 12.0 }.merge(attrs))
    trip.reload
  end

  before { schedule.replace!({ "5" => { adult.id => "1.00" }, "" => { adult.id => "5.00" } }) }

  it "charges the flat paratransit fare inside the urban cities, whatever the distance, guests included" do
    expect(schedule.trip_fare(trip_between("Victoria", "victoria "))).to eq 1.50
    expect(schedule.trip_fare(trip_between("Victoria", "Bloomington", guest_count: 2, attendant_count: 1))).to eq 4.50
  end

  it "falls back to the distance table when either end is outside, or the rider is not ADA eligible, or the fare is off" do
    expect(schedule.trip_fare(trip_between("Victoria", "Port Lavaca"))).to eq 5.00
    rider.update_column(:ada_eligible, false)
    expect(schedule.trip_fare(trip_between("Victoria", "Victoria"))).to eq 5.00
    rider.update_column(:ada_eligible, true)
    provider.update!(fare_paratransit: 0)
    expect(FareSchedule.new(provider).trip_fare(trip_between("Victoria", "Victoria"))).to eq 5.00
  end

  it "prices paratransit through a card tap at pickup" do
    trip = trip_between("Victoria", "Victoria")
    token = FareToken.create!(provider: provider, customer: rider, kind: "rfid", uid: "04A3B2C1")
    FareLedger.new(rider, provider: provider).load!(10, payment_method: "cash")
    r = FareTap.new(provider: provider).trip!(trip: trip, uid: token.uid, client_uuid: SecureRandom.uuid)
    expect(r.fare).to eq 1.50
    expect(rider.reload.fare_balance).to eq 8.50
  end
end

RSpec.describe FareSchedule, "county fares" do
  let(:provider) { create(:provider) }
  let(:adult)    { RiderCategory.find_or_create_by!(name: "Adult") { |c| c.default_fare = 1.00 } }
  let(:senior)   { RiderCategory.find_or_create_by!(name: "Senior 60+") { |c| c.default_fare = 0.50 } }
  let(:schedule) { FareSchedule.new(provider) }

  before do
    adult; senior
    schedule.replace!({ "5" => { adult.id => "1.00", senior.id => "0.50" }, "" => { adult.id => "5.00", senior.id => "2.50" } })
    FareSchedule.new(provider, county: "Calhoun").replace!({ "5" => { adult.id => "2.00", senior.id => "1.50" }, "45" => { adult.id => "7.00", senior.id => "5.00" } })
    { ["town", "Edna"] => [3, 2], ["county", nil] => [5, 2.5], ["other_county", nil] => [15, 10], ["city", "Houston"] => [65, 32.5] }.each do |(zone, place), (full, reduced)|
      FareZoneRow.create!(provider: provider, county: "Jackson", zone: zone, place: place, rider_category: adult, fare: full)
      FareZoneRow.create!(provider: provider, county: "Jackson", zone: zone, place: place, rider_category: senior, fare: reduced)
    end
  end

  def trip_for(home_county:, from: ["Victoria", "Victoria"], to: ["Victoria", "Victoria"], miles: 3.0, **rider_attrs)
    rider = create_rider(provider, **rider_attrs)
    rider.address.update_columns(county: home_county)
    trip, = build_udr_trip(provider, rider)
    trip.pickup_address.update_columns(city: from[0], county: from[1])
    trip.dropoff_address.update_columns(city: to[0], county: to[1])
    trip.update_columns(drive_distance: miles)
    trip.reload
  end

  it "uses the default table for a county without its own" do
    q = schedule.quote(trip_for(home_county: "Victoria"))
    expect(q.amount).to eq 1.00
    expect(q.basis).to eq "standard fare, 3.0 mi"
  end

  it "uses the county's own distance table, chosen by the rider's home county" do
    trip = trip_for(home_county: "calhoun ", from: ["Victoria", "Victoria"], to: ["Port Lavaca", "Calhoun"], miles: 30)
    expect(schedule.trip_fare(trip)).to eq 7.00
    expect(schedule.quote(trip).basis).to eq "Calhoun County fare, 30.0 mi"
  end

  it "is blank past a county table's last band rather than guessing" do
    expect(schedule.trip_fare(trip_for(home_county: "Calhoun", miles: 60))).to be_nil
  end

  it "falls back to the pickup county when the rider has no home county" do
    trip = trip_for(home_county: "", from: ["Port Lavaca", "Calhoun"], to: ["Port Lavaca", "Calhoun"])
    expect(schedule.trip_fare(trip)).to eq 2.00
  end

  it "prices a zone county by where the trip goes, in either direction" do
    within_edna = trip_for(home_county: "Jackson", from: ["Edna", "Jackson"], to: ["edna", "Jackson"])
    in_county   = trip_for(home_county: "Jackson", from: ["Edna", "Jackson"], to: ["Ganado", "Jackson"])
    to_victoria = trip_for(home_county: "Jackson", from: ["Edna", "Jackson"], to: ["Victoria", "Victoria"])
    home_again  = trip_for(home_county: "Jackson", from: ["Victoria", "Victoria"], to: ["Edna", "Jackson"])
    houston     = trip_for(home_county: "Jackson", from: ["Edna", "Jackson"], to: ["Houston", "Harris"])
    elsewhere   = trip_for(home_county: "Jackson", from: ["Edna", "Jackson"], to: ["Austin", "Travis"])
    expect([within_edna, in_county, to_victoria, home_again, houston].map { |t| schedule.trip_fare(t) }).to eq [3, 5, 15, 15, 65]
    expect(schedule.quote(to_victoria).basis).to eq "Jackson County fare, to another county"
    expect(schedule.trip_fare(elsewhere)).to be_nil
  end

  it "charges the rider's category, guests the adult fare, and flags an assumed category" do
    trip = trip_for(home_county: "Jackson", from: ["Edna", "Jackson"], to: ["Houston", "Harris"], default_rider_category_id: senior.id)
    trip.update_columns(guest_count: 1)
    q = schedule.quote(trip.reload)
    expect([q.amount, q.rider, q.guest_each, q.category_assumed]).to eq [32.5 + 65, 32.5, 65, false]
    expect(schedule.quote(trip_for(home_county: "Victoria")).category_assumed).to be true
  end

  it "quotes a rider marked elderly at the senior fare" do
    q = schedule.quote(trip_for(home_county: "Victoria", is_elderly: true))
    expect([q.amount, q.category, q.category_assumed]).to eq [0.50, senior, false]
  end
end

RSpec.describe TripFareQuote do
  let(:provider) { create(:provider) }
  let(:adult)    { RiderCategory.find_or_create_by!(name: "Adult") { |c| c.default_fare = 1.00 } }

  it "prefers an amount typed on the trip, else prices it" do
    FareSchedule.new(provider).replace!({ "" => { adult.id => "2.00" } })
    trip, = build_udr_trip(provider, create_rider(provider, default_rider_category_id: adult.id))
    trip.update_columns(drive_distance: 4.0)
    expect(TripFareQuote.new(trip.reload, compute_distance: false).call.amount).to eq 2.00
    trip.update_columns(fare_amount: 3.25)
    q = TripFareQuote.new(trip.reload, compute_distance: false).call
    expect([q.amount, q.basis]).to eq [3.25, "set on the trip"]
  end
end

RSpec.describe FareSchedule, "rider category from passenger tracking" do
  let(:provider) { create(:provider) }
  let(:adult)    { RiderCategory.find_or_create_by!(name: "Adult") { |c| c.default_fare = 1.00 } }
  let(:senior)   { RiderCategory.find_or_create_by!(name: "Senior 60+") { |c| c.default_fare = 0.50 } }
  let(:disabled) { RiderCategory.find_or_create_by!(name: "Disabled") { |c| c.default_fare = 0.50 } }
  let(:schedule) { FareSchedule.new(provider) }

  before do
    schedule.replace!({ "" => { adult.id => "2.00", senior.id => "1.00", disabled.id => "0.75" } })
  end

  def trip_with(rider_attrs = {}, **trip_attrs)
    trip, = build_udr_trip(provider, create_rider(provider, **rider_attrs))
    trip.update_columns(**{ drive_distance: 3.0 }.merge(trip_attrs))
    trip.reload
  end

  it "prices the rider as Disabled or Senior when the trip counts them and the customer has no category" do
    q = schedule.quote(trip_with(number_of_disabled_passengers_served: 1))
    expect([q.amount, q.category, q.category_source, q.category_assumed]).to eq [0.75, disabled, :trip_tracking, false]
    q = schedule.quote(trip_with(number_of_senior_passengers_served: 1))
    expect([q.amount, q.category, q.category_source]).to eq [1.00, senior, :trip_tracking]
  end

  it "keeps the customer's own category ahead of the trip's counts" do
    q = schedule.quote(trip_with({ default_rider_category_id: adult.id }, number_of_disabled_passengers_served: 1))
    expect([q.amount, q.category_source]).to eq [2.00, :customer]
  end

  it "still charges guests the adult fare" do
    q = schedule.quote(trip_with(number_of_disabled_passengers_served: 2, guest_count: 1))
    expect([q.rider, q.guest_each, q.amount]).to eq [0.75, 2.00, 2.75]
  end

  it "is Adult, assumed, with no category and no counts" do
    q = schedule.quote(trip_with)
    expect([q.amount, q.category_source, q.category_assumed]).to eq [2.00, :assumed, true]
  end
end
