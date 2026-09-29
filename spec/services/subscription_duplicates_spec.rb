require "rails_helper"

RSpec.describe SubscriptionDuplicates do
  let(:provider) { create(:provider) }
  let(:customer) { create(:customer, provider: provider) }
  let(:home)     { create(:address, address: "100 Main St", city: "Victoria") }
  let(:clinic)   { create(:address, address: "1405 Victoria Station Dr", city: "Victoria") }
  let(:monday)   { Date.current.next_occurring(:monday) }
  let!(:existing) do
    create(:repeating_trip, provider: provider, customer: customer, pickup_address: home, dropoff_address: clinic,
           start_date: monday, pickup_time: Time.zone.parse("#{monday} 08:00"),
           repeats_mondays: true, repeats_wednesdays: true, repeats_fridays: true)
  end

  def check(**overrides)
    params = ActionController::Parameters.new({
      customer_id: customer.id.to_s, start_date: monday.strftime("%a %b %d, %Y"), end_date: "",
      pickup_time: "08:00 AM", pickup_address_id: home.id.to_s, dropoff_address_id: clinic.id.to_s,
      repeats_mondays: "1", repeats_wednesdays: "0", repeats_fridays: "0"
    }.merge(overrides)).permit!
    described_class.new(params, provider.id).matches.map { |m| m[:id] }
  end

  it "flags a second copy of the same ride" do
    expect(check).to eq [existing.id]
  end

  it "flags the same days at a nearby time even with different addresses" do
    expect(check(pickup_time: "08:30 AM", pickup_address_id: "", dropoff_address_id: "")).to eq [existing.id]
  end

  it "flags the same places even at a different time (Home to Dialysis twice)" do
    expect(check(pickup_time: "12:00 PM")).to eq [existing.id]
  end

  it "leaves the ride home alone: addresses swapped and hours later" do
    expect(check(pickup_time: "01:30 PM", pickup_address_id: clinic.id.to_s, dropoff_address_id: home.id.to_s)).to be_empty
  end

  it "needs a weekday in common" do
    expect(check(repeats_mondays: "0", repeats_tuesdays: "1")).to be_empty
  end

  it "ignores the subscription being edited and other riders" do
    expect(check(id: existing.id.to_s)).to be_empty
    expect(check(customer_id: create(:customer, provider: provider).id.to_s)).to be_empty
  end

  it "ignores a subscription that ended before this one starts" do
    existing.update_columns(end_date: monday - 1.day)
    expect(check).to be_empty
  end
end

RSpec.describe RepeatingTripsController, "check_duplicates", type: :controller do
  login_admin_as_current_user

  it "answers with the matching subscriptions" do
    allow_any_instance_of(SubscriptionDuplicates).to receive(:matches).and_return([{ id: 7, days: "Mon" }])
    post :check_duplicates, params: { repeating_trip: { customer_id: 1, repeats_mondays: "1" } }, format: :json
    expect(JSON.parse(response.body)).to eq("trips" => [{ "id" => 7, "days" => "Mon" }])
  end
end
