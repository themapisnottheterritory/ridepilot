require "rails_helper"

RSpec.describe FooterNote do
  it "shows the same quote all day and the next one tomorrow" do
    day = Date.new(2026, 9, 29)
    expect(described_class.quote(day)).to be_present
    expect(described_class.quote(day)).to eq described_class.quote(day)
    expect(described_class.quote(day + 1)).not_to eq described_class.quote(day)
  end

  it "counts only today's completed rides for the provider" do
    provider = create(:provider)
    comp = create(:trip_result, code: "COMP")
    ns = create(:trip_result, code: "NS")
    now = Time.zone.now.change(hour: 10)
    ride = ->(attrs) { t = build(:trip, { provider: provider, pickup_time: now }.merge(attrs)); t.save!(validate: false); t }
    ride.(trip_result: comp)
    ride.(trip_result: comp)
    ride.(trip_result: ns)                                   # no-show
    ride.(trip_result: nil)                                  # not marked yet
    ride.(trip_result: comp, pickup_time: now - 1.day)       # yesterday
    ride.(trip_result: comp, provider: create(:provider))    # another county
    expect(described_class.rides_completed(provider, now.to_date)).to eq 2
  end

  it "says nothing until there is a ride to count" do
    expect(described_class.rides_text(0)).to be_nil
    expect(described_class.rides_text(1)).to eq "Today so far: 1 ride got a neighbor where they chose to go."
    expect(described_class.rides_text(12)).to eq "Today so far: 12 rides got neighbors where they chose to go."
  end
end

RSpec.describe FooterController, type: :controller do
  login_admin_as_current_user

  it "reports today's rides for the signed-in provider" do
    allow(FooterNote).to receive(:rides_completed).and_return(3)
    get :today
    expect(JSON.parse(response.body)).to eq("count" => 3, "text" => "Today so far: 3 rides got neighbors where they chose to go.")
  end
end
