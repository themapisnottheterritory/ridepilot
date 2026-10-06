require "rails_helper"

# Where our towns are, for keeping address answers near the town typed (2026-10-06).
RSpec.describe TownCentres do
  let(:towns) { { "victoria" => { name: "Victoria", n: 11269, lat: 28.813, lon: -96.990 },
                  "port lavaca" => { name: "Port Lavaca", n: 1537, lat: 28.615, lon: -96.628 },
                  "hallettsville" => { name: "Hallettsville", n: 1016, lat: 29.444, lon: -96.941 },
                  "houston" => { name: "Houston", n: 4, lat: 29.73, lon: -95.378 } } }
  before { allow(described_class).to receive(:all).and_return(towns) }

  it "takes the last town in the text" do
    expect(described_class.find_in("502 Victoria St, Port Lavaca, TX")[:name]).to eq "Port Lavaca"
    expect(described_class.find_in("33 Seakist Rd Port Lavaca TX 77979")).to include(name: "Port Lavaca", typed: "port lavaca")
  end

  it "doesn't take a street named after a town for the town" do
    expect(described_class.find_in("4001 Houston Highway")).to be_nil
    expect(described_class.find_in("4001 Houston Hwy, Victoria")[:name]).to eq "Victoria"
  end

  it "takes a town one letter off" do
    expect(described_class.find_in("1400 e cemetery hallettsvile")).to include(name: "Hallettsville", typed: "hallettsvile")
    expect(described_class.find_in("12 Main")).to be_nil
  end

  it "knows the area we serve from the towns with many addresses" do
    expect(described_class.served?(28.80, -96.98)).to be true      # Victoria
    expect(described_class.served?(29.73, -95.38)).to be false     # Houston: 4 addresses, not our area
  end
end
