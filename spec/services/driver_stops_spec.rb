require "rails_helper"

# Where drivers stop (2026-10-03): a spot is learned only when visits on 3+ days
# agree, and a pin far from it is listed for staff, never moved automatically.
RSpec.describe DriverStops do
  let(:provider) { create(:provider) }
  let(:home) { create(:address, type: "CustomerCommonAddress", provider: provider, the_geom: Address.compute_geom(28.80000, -97.00000)) }
  # about 640 m north-east of the pin
  let(:spot) { [28.80450, -96.99550] }

  def visit!(address, lat, lon, at)
    @n = (@n || 0) + 1
    StopSighting.create!(address_id: address.id, itinerary_id: 900_000 + @n, provider_id: provider.id,
                         seen_at: at, latitude: lat, longitude: lon, dwell_secs: 90)
  end

  def three_days_at(address, lat, lon)
    3.times { |d| visit!(address, lat + d * 0.00005, lon, (d + 1).days.ago) }   # ~5 m apart
  end

  describe ".learned" do
    it "learns a spot once visits on three days agree" do
      three_days_at(home, *spot)
      l = DriverStops.learned([home.id])[home.id]
      expect(l[:days]).to eq 3
      expect(DriverStops.meters(l[:lat], l[:lon], *spot)).to be < 10
    end

    it "doesn't learn from two days" do
      2.times { |d| visit!(home, *spot, (d + 1).days.ago) }
      expect(DriverStops.learned([home.id])).to be_empty
    end

    it "doesn't learn when the visits disagree" do
      three_days_at(home, *spot)
      3.times { |d| visit!(home, 28.79, -97.02 - d * 0.01, (d + 4).days.ago) }   # scattered elsewhere
      expect(DriverStops.learned([home.id])).to be_empty
    end
  end

  describe ".pins_to_check" do
    it "lists a pin far from where drivers stop" do
      three_days_at(home, *spot)
      row = DriverStops.pins_to_check([provider.id]).first
      expect(row[:address].id).to eq home.id
      expect(row[:distance_m]).to be_between(550, 750)
    end

    it "leaves out a pin that drivers stop near" do
      three_days_at(home, 28.80030, -97.00000)   # ~33 m
      expect(DriverStops.pins_to_check([provider.id])).to be_empty
    end

    it "never offers a saved place's spot for a rider's home" do
      create(:address, type: "ProviderCommonAddress", provider: provider, inactive: false, the_geom: Address.compute_geom(*spot))
      three_days_at(home, *spot)
      expect(DriverStops.pins_to_check([provider.id])).to be_empty
    end

    it "drops a pin once someone has decided, until drivers stop there again" do
      three_days_at(home, *spot)
      PinCheck.create!(address_id: home.id, decision: "kept")
      expect(DriverStops.pins_to_check([provider.id])).to be_empty
      visit!(home, *spot, 1.minute.from_now)
      expect(DriverStops.pins_to_check([provider.id]).size).to eq 1
    end
  end
  describe ".sequence_match (stops tapped in a burst)" do
    let(:day) { Date.current - 1 }
    let(:van) { create(:vehicle, provider: provider, name: "1780") }
    let(:run) { create(:run, provider: provider, vehicle: van, date: day, scheduled_start_time: day.in_time_zone.change(hour: 7), scheduled_end_time: day.in_time_zone.change(hour: 17), actual_start_time: day.in_time_zone.change(hour: 7)) }
    let(:t0) { day.in_time_zone.change(hour: 14) }
    let!(:stops) do
      [[28.80, -97.00], [28.81, -97.00], [28.82, -97.00]].each_with_index.map do |(la, lo), k|
        a = create(:address, type: "CustomerCommonAddress", provider: provider, the_geom: Address.compute_geom(la, lo))
        trip = create(:trip, provider: provider, run: run, pickup_time: t0, appointment_time: t0 + 30.minutes)
        Itinerary.create!(run: run, trip: trip, leg_flag: 1, address_id: a.id, time: t0, finish_time: t0 + k * 20.seconds, status_code: 2)
      end
    end
    before { run.update_column(:manifest_order, stops.map(&:itin_id)) }
    def halt(min, lat) = DriverStops::Halt.new(unit: "1780", from: t0 - min.minutes, to: t0 - min.minutes + 90, lat: lat, lon: -97.0)

    it "pairs the burst's stops with the van's halts in manifest order when the counts match" do
      halts = { "1780" => [halt(50, 28.8001), halt(35, 28.8101), halt(20, 28.8201)] }
      expect(DriverStops.sequence_match(run.reload, stops.map(&:reload), halts, Set.new)).to eq 3
      got = StopSighting.where(itinerary_id: stops.map(&:id)).order(:seen_at).map { |x| x.latitude.round(3) }
      expect(got).to eq [28.8, 28.81, 28.82]
      expect(StopSighting.pluck(:source).uniq).to eq ["sequence"]
    end

    it "skips the burst when the van stopped more times than there are stops" do
      halts = { "1780" => [halt(55, 28.79), halt(50, 28.8001), halt(35, 28.8101), halt(20, 28.8201)] }
      expect(DriverStops.sequence_match(run.reload, stops.map(&:reload), halts, Set.new)).to eq 0
      expect(StopSighting.count).to eq 0
    end
  end
end
