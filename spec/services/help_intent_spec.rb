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

  it "answers nil, not an error, when the model server is down or talks nonsense" do
    allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED)
    expect(described_class.detect("add 1 Main St")).to be_nil
    allow(Net::HTTP).to receive(:start).and_return(double(code: "200", body: { choices: [{ message: { content: "not json" } }] }.to_json))
    expect(described_class.detect("add 1 Main St")).to be_nil
  end
end
