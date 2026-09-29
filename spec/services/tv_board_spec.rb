require "rails_helper"

RSpec.describe TvBoard do
  include ActiveSupport::Testing::TimeHelpers
  let(:provider) { create(:provider) }
  let(:now) { Time.zone.now.change(hour: 10) }
  before { travel_to(now) }
  after { travel_back }

  def trip_at(time, **attrs)
    t = build(:trip, { provider: provider, pickup_time: time, appointment_time: nil, run: nil }.merge(attrs))
    t.save!(validate: false)
    t
  end

  it "turns red when a pickup within two hours has no run" do
    trip_at(now + 1.hour)
    hero = described_class.new(provider).as_json[:hero]
    expect([hero[:count], hero[:tone], hero[:text]]).to eq [1, "crit", "1 pickup within 2 hours needs a run"]
  end

  it "is amber for later trips without a run, and green when everything has one" do
    t = trip_at(now + 5.hours)
    expect(described_class.new(provider).as_json[:hero][:tone]).to eq "warn"
    run = create(:run, provider: provider, date: now.to_date)
    t.update_columns(run_id: run.id)
    expect(described_class.new(provider).as_json[:hero].values_at(:count, :tone)).to eq [0, "good"]
  end

  it "counts only trips still to come; past ones are just mentioned" do
    trip_at(now - 3.hours)
    trip_at(now + 5.hours)
    hero = described_class.new(provider).as_json[:hero]
    expect(hero.values_at(:count, :past_count, :tone)).to eq [1, 1, "warn"]
  end

  it "is covered once the day's remaining trips have runs, pointing at tomorrow" do
    trip_at(now - 3.hours)
    trip_at(now + 1.day)
    hero = described_class.new(provider).as_json[:hero]
    expect(hero.values_at(:count, :tone, :text)).to eq [0, "warn", "Today is covered · tomorrow needs runs"]
  end

  it "doesn't count cancelled trips as needing a run" do
    trip_at(now + 1.hour, trip_result: create(:trip_result, code: "CANC"))
    expect(described_class.new(provider).as_json[:hero][:count]).to eq 0
  end

  it "shows started runs on the road with their progress, and no rider names" do
    run = create(:run, provider: provider, date: now.to_date, name: "UDR1")
    run.update_columns(actual_start_time: now - 1.hour, actual_end_time: nil)
    trip_at(now - 30.minutes, run: run, trip_result: create(:trip_result, code: "COMP"))
    trip_at(now + 30.minutes, run: run)
    board = described_class.new(provider).as_json
    expect(board[:on_road].first.values_at(:name, :done, :total, :fixed)).to eq ["UDR1", 1, 2, false]
    expect(board.to_json).not_to include(Trip.first.customer.last_name)
  end

  it "summarises today and the next two days" do
    trip_at(now + 1.day)
    days = described_class.new(provider).as_json[:days]
    expect(days.map { |d| d[:label] }.first(2)).to eq %w[Today Tomorrow]
    expect(days[1].values_at(:booked, :without_run)).to eq [1, 1]
  end
end

RSpec.describe TvController, type: :controller do
  before { allow(File).to receive(:read).and_call_original }
  around { |ex| ENV["TV_WALL_KEY"] = "sekret"; ex.run; ENV.delete("TV_WALL_KEY") }

  it "needs the key, and no sign-in" do
    get :data, params: { k: "wrong" }
    expect(response.status).to eq 403
    provider = create(:provider)
    get :data, params: { k: "sekret", p: provider.id }
    expect(response.status).to eq 200
    expect(JSON.parse(response.body).keys).to include("hero", "on_road", "days", "strip")
  end
end
