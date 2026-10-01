require "rails_helper"

# 2026-10-01: the address dialog sent longitudes as bare digits and the point
# factory wrapped them half a world away (Timothy Pergrem's home at -84).
RSpec.describe Address, ".compute_geom" do
  def lonlat(geom) = [geom.x.round(6), geom.y.round(6)]

  it "places an ordinary point" do
    expect(lonlat(Address.compute_geom("29.481464", "-97.651140"))).to eq [-97.65114, 29.481464]
  end

  it "puts back a longitude that arrived as bare digits" do
    expect(lonlat(Address.compute_geom("29.481464527995804", "9765114006172236"))).to eq [-97.65114, 29.481465]
    expect(lonlat(Address.compute_geom("28.68516940550856", "9645446842019332"))).to eq [-96.454468, 28.685169]
  end

  it "gives no pin rather than a wrapped one for anything else impossible" do
    expect(Address.compute_geom("29.48", "-284.0")).to be_nil
    expect(Address.compute_geom("29.48", "1234567")).to be_nil        # digits that don't land in the area
    expect(Address.compute_geom("129.48", "-97.6")).to be_nil
    expect(Address.compute_geom("29.48", "abc")).to be_nil
  end

  it "leaves blank alone" do
    expect(Address.compute_geom("", "-97.6")).to be_nil
  end
end
