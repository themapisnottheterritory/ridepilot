require "rails_helper"

RSpec.describe TownBadgeHelper, type: :helper do
  let(:cuero)    { build(:address, city: "Cuero") }
  let(:victoria) { build(:address, city: " Victoria ") }

  it "is green in the rider's town, amber in another, plain with no rider" do
    expect(helper.town_badge(victoria, build(:address, city: "victoria"))).to include('class="town-chip home no-export"', ">Victoria<")
    away = helper.town_badge(cuero, victoria)
    expect(away).to include('class="town-chip away no-export"', "Not the rider&#39;s town (Victoria)")
    expect(helper.town_badge(cuero)).to include('class="town-chip no-export"')
  end

  it "shows nothing without a town" do
    expect(helper.town_badge(nil)).to be_nil
    expect(helper.town_badge(build(:address, city: " "))).to be_nil
  end
end

RSpec.describe TownCentres do
  it "boxes the towns we serve, not the far ones a few trips go to" do
    allow(TownCentres).to receive(:all).and_return(
      "victoria" => { name: "Victoria", n: 900, lat: 28.8, lon: -97.0 },
      "cuero"    => { name: "Cuero", n: 40, lat: 29.1, lon: -97.3 },
      "houston"  => { name: "Houston", n: 12, lat: 29.76, lon: -95.37 })
    box = TownCentres.served_box
    expect(box[:min_lon]).to be_within(0.001).of(-97.45)
    expect(box[:max_lon]).to be_within(0.001).of(-96.85)
    expect(box[:max_lat]).to be_within(0.001).of(29.25)
  end
end
