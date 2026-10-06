require "rails_helper"

# Typed coordinates (the trip form's Lat/Lon) that can't be right.
RSpec.describe Address, ".compute_geom" do
  it "puts back a longitude's missing minus sign (MATA1, 2026-10-06)" do
    g = Address.compute_geom("28.942688886059837", "95.96540583105735")
    expect([g.y.round(4), g.x.round(4)]).to eq [28.9427, -95.9654]
  end

  it "gives no pin outside Texas" do
    expect(Address.compute_geom(-1, 1)).to be_nil
    expect(Address.compute_geom(48.8, -101.0)).to be_nil      # North Dakota
  end

  it "keeps a good point as it is" do
    g = Address.compute_geom(28.8133, -96.9864)
    expect([g.y, g.x]).to eq [28.8133, -96.9864]
  end
end
