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
end
