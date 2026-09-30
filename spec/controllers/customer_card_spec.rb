require "rails_helper"

# The hover card on customer names, and the Trips panel's last 10 / next 10.
RSpec.describe CustomersController, "card", type: :controller do
  login_admin_as_current_user
  render_views

  let(:provider) { @current_user.current_provider }
  let(:customer) { create(:customer, provider: provider, first_name: "Allan", last_name: "Velasquez", phone_number_1: "(361) 555-0101", message: "Needs a call before pickup") }

  def trip_at(time, result: nil)
    t = build(:trip, customer: customer, provider: provider, pickup_time: time, appointment_time: nil)
    t.trip_result = TripResult.find_by(code: result) || create(:trip_result, code: result, name: result.titleize) if result
    t.save!(validate: false); t
  end

  it "shows who the customer is, their flag, and their next and last trip" do
    trip_at(2.days.ago, result: "COMP")
    trip_at(3.days.from_now)
    get :card, params: { id: customer.id }
    expect(response.status).to eq 200
    expect(response.body).to include("Velasquez", "(361) 555-0101", "Needs a call before pickup", "Next", "Last")
    expect(response.body).not_to include("<html")
  end

  it "won't show another agency's customer" do
    other = create(:customer, provider: create(:provider))
    allow_any_instance_of(Customer).to receive(:authorized_for_provider).and_return(false)
    get :card, params: { id: other.id }
    expect(response.status).to eq 403
  end
end

RSpec.describe CustomerTrips do
  it "splits a customer's trips into the latest past ones and the soonest coming ones, 10 each" do
    customer = create(:customer)
    now = Time.zone.parse("2026-09-30 12:00")
    times = (-12..12).map { |d| now + d.days }
    times.each { |t| build(:trip, customer: customer, provider: customer.provider, pickup_time: t, appointment_time: nil).save!(validate: false) }
    ct = described_class.new(customer, now: now)
    expect(ct.coming.map(&:pickup_time)).to eq times.select { |t| t >= now }.first(10)
    expect(ct.recent.map(&:pickup_time)).to eq times.select { |t| t < now }.last(10).reverse
    expect(ct.last_and_next.map(&:pickup_time)).to eq [now - 1.day, now]
  end
end
