require "rails_helper"

# Kelly, 2026-09-29: a typed drop-off on the subscription form was refused as
# "Dropoff address can't be blank / must exist" -- the subscription form
# didn't resolve typed addresses the way the trip form does.
RSpec.describe RepeatingTripsController, "typed addresses", type: :controller do
  login_admin_as_current_user
  let(:provider) { @current_user.current_provider }
  let(:customer) { create(:customer, provider: provider) }
  let(:clinic) { create(:provider_common_address, provider: provider, name: "Dialysis", address: "200 Medical Center", city: "Bay City", state: "TX", zip: "77414") }
  let(:home) do
    a = CustomerCommonAddress.new(customer: customer, provider: provider, name: "Home", address: "3705 5th Street", city: "Bay City", state: "TX", zip: "77414")
    a.the_geom = Address.compute_geom(28.98, -95.96)
    a.save!(validate: false)
    a
  end

  def post_subscription(dropoff_text)
    post :create, params: {
      repeating_trip: { customer_id: customer.id, pickup_address_id: clinic.id, dropoff_address_id: "",
                        pickup_time: "08:00 AM", appointment_time: "08:30 AM", trip_purpose_id: create(:trip_purpose).id,
                        start_date: Date.current.strftime("%a %b %d, %Y"), repeats_mondays: "1", repetition_interval: 1 },
      dropoff_address: dropoff_text
    }
  end

  before { clinic.update_columns(the_geom: Address.compute_geom(28.97, -95.97)) }

  it "uses the rider's saved address when the drop-off was typed rather than picked" do
    home
    post_subscription("Home 3705 5th Street Bay City, TX 77414")
    expect(assigns(:trip).dropoff_address).to eq home
    expect(assigns(:trip).errors[:dropoff_address]).to be_empty
  end

  it "explains what to do when a typed address can't be found" do
    allow(GeocodingService).to receive(:new).and_return(double(execute: []))
    post_subscription("somewhere that is not a place")
    expect(assigns(:trip).errors[:dropoff_address].join).to include("couldn't be located", "pick a match from the suggestions")
  end
end
