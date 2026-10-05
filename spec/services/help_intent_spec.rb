require "rails_helper"

# Ask RidePilot: reading a request out of a message (the model fills a form, Ruby checks it).
RSpec.describe HelpIntent do
  it "skips the model for a message that cannot be a request" do
    expect(Net::HTTP).not_to receive(:start)
    expect(described_class.detect("Where is the fare shown?")).to be_nil
  end

  it "keeps only a request it knows, with its fields trimmed" do
    reply = { intent: "add_saved_place", name: " VA Clinic ", address: "311 Spring Green Blvd", city: nil, state: "TX", zip: "77904", category: "Medical", extra: "x" }.to_json
    res = double(code: "200", body: { choices: [{ message: { content: reply } }] }.to_json)
    allow(Net::HTTP).to receive(:start).and_return(res)
    expect(described_class.detect("please add 311 Spring Green Blvd its the VA Clinic")).to eq(
      "intent" => "add_saved_place", "name" => "VA Clinic", "address" => "311 Spring Green Blvd", "city" => nil, "state" => "TX", "zip" => "77904", "category" => "Medical")
    res2 = double(code: "200", body: { choices: [{ message: { content: '{"intent":"none"}' } }] }.to_json)
    allow(Net::HTTP).to receive(:start).and_return(res2)
    expect(described_class.detect("How do I add a saved address?")).to be_nil
  end

  it "knows a request to find a place on the map" do
    reply = { intent: "find_place", name: "Walmart", address: "Navarro", city: "Victoria" }.to_json
    allow(Net::HTTP).to receive(:start).and_return(double(code: "200", body: { choices: [{ message: { content: reply } }] }.to_json))
    expect(described_class.detect("where is the Walmart on Navarro? find it on the map")).to include("intent" => "find_place", "address" => "Navarro")
  end

  it "answers nil, not an error, when the model server is down or talks nonsense" do
    allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED)
    expect(described_class.detect("add 1 Main St")).to be_nil
    allow(Net::HTTP).to receive(:start).and_return(double(code: "200", body: { choices: [{ message: { content: "not json" } }] }.to_json))
    expect(described_class.detect("add 1 Main St")).to be_nil
  end

  # 2026-10-05: "where is Kuecker service center in Cuero?" skipped the model.
  it "asks the model about where a place is in a town, but not about where something is shown" do
    reply = { intent: "find_place", name: "Kuecker Service Center", address: nil, city: "Cuero" }.to_json
    allow(Net::HTTP).to receive(:start).and_return(double(code: "200", body: { choices: [{ message: { content: reply } }] }.to_json))
    expect(described_class.detect("where is Kuecker service center in Cuero?")).to include("intent" => "find_place", "name" => "Kuecker Service Center", "city" => "Cuero")
    expect(described_class::TRIGGER).to match("Where's the HEB on Navarro")
    expect(described_class::TRIGGER).to match("¿Dónde está la clínica en Yoakum?")
    expect(described_class::TRIGGER).not_to match("Where is the fare shown?")
    expect(described_class::TRIGGER).not_to match("Where do I see a rider's trips?")
  end
end
