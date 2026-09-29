require "rails_helper"

RSpec.describe RouteOptimizerService do
  let(:provider) { create(:provider) }
  let(:rider_a)  { create_rider(provider, first_name: "Ann") }
  let(:rider_b)  { create_rider(provider, first_name: "Bob") }
  let!(:setup)   { build_udr_trip(provider, rider_a) }
  let(:run)      { setup[1] }
  let(:day)      { run.date }
  let(:at)       { ->(hhmm) { Time.zone.parse("#{day} #{hhmm}") } }
  let(:trip_a)   { setup[0].tap { |t| t.update_columns(pickup_time: at.("08:00"), appointment_time: at.("08:30")) } }
  let!(:trip_b) do
    t = build(:trip, provider: provider, customer: rider_b, run: run, pickup_time: at.("08:05"), appointment_time: nil)
    t.save!(validate: false)
    t
  end

  before do
    [trip_a, trip_b].each_with_index do |t, i|
      t.pickup_address.update_columns(the_geom: Address.compute_geom(28.80 + i * 0.01, -97.00))
      t.dropoff_address.update_columns(the_geom: Address.compute_geom(28.85, -97.02 - i * 0.01))
    end
    run.update_columns(scheduled_start_time: at.("07:30"), scheduled_end_time: at.("17:00"), actual_start_time: nil)
  end

  def secs(hhmm)
    h, m = hhmm.split(":").map(&:to_i)
    h * 3600 + m * 60
  end

  def reply(status, stops: [], unassigned: [])
    { "run_id" => run.id, "stops" => stops, "unassigned_trip_ids" => unassigned, "solver_status" => status,
      "total_distance_m" => 16093.4, "total_drive_seconds" => 1800 }
  end

  it "sends appointment times as drop-off deadlines and the run's hours" do
    sent = nil
    allow_any_instance_of(described_class).to receive(:post) { |_, payload| sent = payload; reply("fail") }
    described_class.optimize_run(run)
    a = sent[:trips].find { |t| t[:trip_id] == trip_a.id }
    b = sent[:trips].find { |t| t[:trip_id] == trip_b.id }
    expect(a[:latest_dropoff]).to eq secs("08:30")
    expect(b[:latest_dropoff]).to be_nil
    expect([sent[:earliest_start], sent[:latest_end]]).to eq [secs("07:30"), secs("17:00")]
  end

  it "writes the optimizer's interleaved stop sequence as the manifest and sets pickup ETAs" do
    stops = [
      { "trip_id" => trip_a.id, "kind" => "pickup",  "eta" => secs("07:58") },
      { "trip_id" => trip_b.id, "kind" => "pickup",  "eta" => secs("08:04") },
      { "trip_id" => trip_a.id, "kind" => "dropoff", "eta" => secs("08:20") },
      { "trip_id" => trip_b.id, "kind" => "dropoff", "eta" => secs("08:26") }
    ]
    allow_any_instance_of(described_class).to receive(:post).and_return(reply("success", stops: stops))
    result = described_class.optimize_run(run)
    expect(result["applied"]).to be true
    expect(result["message"]).to include("Route optimized: 2 trips, 4 stops, about 10.0 mi and 30 min")
    expect(run.reload.manifest_order).to eq [
      "run_begin", "trip_#{trip_a.id}_leg_1", "trip_#{trip_b.id}_leg_1", "trip_#{trip_a.id}_leg_2", "trip_#{trip_b.id}_leg_2", "run_end"
    ]
    expect(trip_a.reload.estimated_pickup_time).to eq at.("07:58")
    expect(trip_b.reload.estimated_pickup_time).to eq at.("08:04")
  end

  it "changes nothing when some trips don't fit, and says which" do
    before_order = run.manifest_order
    allow_any_instance_of(described_class).to receive(:post)
      .and_return(reply("partial", stops: [{ "trip_id" => trip_a.id, "kind" => "pickup", "eta" => 1 }], unassigned: [trip_b.id]))
    result = described_class.optimize_run(run)
    expect(result["applied"]).to be false
    expect(result["message"]).to include("Not changed", rider_b.name, "8:05 AM")
    expect(run.reload.manifest_order).to eq before_order
    expect(trip_a.reload.estimated_pickup_time).to be_nil
  end

  it "leaves a run that has started alone, without calling the optimizer" do
    run.update_columns(actual_start_time: at.("07:31"))
    expect_any_instance_of(described_class).not_to receive(:post)
    result = described_class.optimize_run(run)
    expect([result["solver_status"], result["applied"]]).to eq ["skipped", false]
    expect(result["message"]).to include("has started")
  end
end

RSpec.describe RunsController, "optimize", type: :controller do
  login_admin_as_current_user

  it "runs the optimizer and reports the result on the run page" do
    provider = @current_user.current_provider
    trip, run, = build_udr_trip(provider, create_rider(provider))
    allow(RouteOptimizerService).to receive(:optimize_run).and_return({ "applied" => false, "message" => "Not changed: X" })
    post :optimize, params: { id: run.id }
    expect(response).to redirect_to(run_path(run))
    expect(flash[:alert]).to eq "Not changed: X"
  end
end

RSpec.describe FleetOptimizerService do
  let(:provider) { create(:provider) }

  it "moves trips first, then rebuilds each run, so a run keeps no stops for trips it lost" do
    t1, run1, driver = build_udr_trip(provider, create_rider(provider))
    t2 = build(:trip, provider: provider, customer: create_rider(provider), run: run1, pickup_time: t1.pickup_time + 10.minutes)
    t2.save!(validate: false)
    vehicle2 = build(:vehicle, provider: provider); vehicle2.save!(validate: false)
    run2 = create(:run, provider: provider, vehicle: vehicle2, date: run1.date)
    run1.reset_itineraries
    result = { "solver_status" => "success", "unassigned_trip_ids" => [], "runs" => [
      { "run_id" => run1.id, "stops" => [{ "trip_id" => t1.id, "kind" => "pickup", "eta" => 28800 }, { "trip_id" => t1.id, "kind" => "dropoff", "eta" => 29400 }] },
      { "run_id" => run2.id, "stops" => [{ "trip_id" => t2.id, "kind" => "pickup", "eta" => 29000 }, { "trip_id" => t2.id, "kind" => "dropoff", "eta" => 29600 }] }
    ] }
    described_class.new(provider, run1.date).send(:apply_result, result)
    expect(t2.reload.run_id).to eq run2.id
    expect(run1.reload.itineraries.where(leg_flag: [1, 2]).pluck(:trip_id).uniq).to eq [t1.id]
    expect(run2.reload.itineraries.where(leg_flag: [1, 2]).pluck(:trip_id).uniq).to eq [t2.id]
    expect(run2.manifest_order).to eq ["run_begin", "trip_#{t2.id}_leg_1", "trip_#{t2.id}_leg_2", "run_end"]
  end
end
