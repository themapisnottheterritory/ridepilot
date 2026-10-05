require "rails_helper"

# Busy unnamed trip destinations, and naming them (Phil, 2026-10-05: callers ask
# about "Victoria Heart and Vascular", trips show "2401 Patterson Drive").
RSpec.describe PlaceNaming do
  let(:provider) { create(:provider) }
  let(:admin)    { create(:admin, current_provider: provider) }
  let(:group)    { create(:address_group) }

  def typed(address, city: "Victoria", name: nil, lat: 28.8133, lon: -96.9864)
    TempAddress.create!(address: address, city: city, state: "TX", zip: "77901", name: name, provider: provider,
                        the_geom: Address.compute_geom(lat, lon))
  end

  def trip_to(address, days_from_now: 1)
    t = create(:trip, provider: provider, customer: create(:customer, provider: provider), dropoff_address: address,
                      pickup_time: Time.zone.now.beginning_of_day + 1.day + 9.hours, appointment_time: nil)
    # trips can only be booked 21 days ahead; move a far one afterwards
    t.update_columns(pickup_time: Time.zone.now.beginning_of_day + days_from_now.days + 9.hours) if days_from_now != 1
    t
  end

  it "lists unnamed destinations busiest first, one row per street address, without named or skipped ones" do
    a1 = typed("2401 Patterson Drive"); a2 = typed("2401 PATTERSON DR.")   # two typed copies of one place
    3.times { trip_to(a1) }; trip_to(a2)
    trip_to(typed("2550 North Esplanade Street", city: "Cuero"))
    trip_to(typed("909 E Broadway", city: "Cuero", name: "Cuero H-E-B"))
    trip_to(typed("1 Far Away St"), days_from_now: 60)                      # outside the window
    trip_to(typed("702 Salem Rd APT 513"))                                  # an apartment: someone's home
    rider = create(:customer, provider: provider)
    CustomerCommonAddress.create!(customer: rider, name: "Home", address: "222 Sirocco", city: "Victoria", state: "TX")
    2.times { trip_to(typed("222 Sirocco")) }                               # a rider's saved home, typed again
    rows = described_class.unnamed_destinations(provider)
    expect(rows.map { |r| [r[:address], r[:trips]] }).to eq [["2401 Patterson Drive", 4], ["2550 North Esplanade Street", 1]]
    expect(rows.first[:address_ids]).to contain_exactly(a1.id, a2.id)
    described_class.skip!(provider, rows.last[:key])
    expect(described_class.unnamed_destinations(provider).size).to eq 1
  ensure
    File.delete(described_class.skip_path(provider)) rescue nil
  end

  it "names a place: a saved place, and every unnamed copy of the address, not named ones" do
    a1 = typed("2401 Patterson Drive"); a2 = typed("2401 PATTERSON DR.")
    other = typed("2401 Patterson Drive", name: "Suite B Dentist")
    elsewhere = typed("2104 Patterson Drive")
    result = described_class.name_place!(provider: provider, user: admin, address_ids: [a1.id], name: " Victoria Heart & Vascular ", address_group_id: group.id)
    expect(result[:saved_place]).to have_attributes(name: "Victoria Heart & Vascular", address: "2401 Patterson Drive", provider_id: provider.id, address_group_id: group.id)
    expect(result[:renamed]).to eq 2
    expect([a1, a2, other, elsewhere].map { |a| a.reload.name }).to eq ["Victoria Heart & Vascular", "Victoria Heart & Vascular", "Suite B Dentist", nil]
  end

  it "refuses a blank name" do
    a1 = typed("2401 Patterson Drive")
    expect { described_class.name_place!(provider: provider, user: admin, address_ids: [a1.id], name: " ", address_group_id: group.id) }.to raise_error(ArgumentError)
    expect(ProviderCommonAddress.count).to eq 0
  end

  it "gives a newly typed address the saved place's name, by address or by a pin a few metres away" do
    create(:provider_common_address, provider: provider, name: "Victoria Heart & Vascular", address: "2401 Patterson Dr",
           city: "Victoria", state: "TX", the_geom: Address.compute_geom(28.8133, -96.9864))
    expect(typed("2401 Patterson Drive").name).to eq "Victoria Heart & Vascular"
    expect(typed("2401 Patterson Drive, Suite 100", lat: 28.81335, lon: -96.98645).name).to eq "Victoria Heart & Vascular"   # 6 m, same number
    expect(typed("2104 Patterson Drive", lat: 28.8134, lon: -96.9865).name).to be_nil                                        # another number
    expect(typed("2401 Patterson Drive", name: "Typed name").name).to eq "Typed name"                                       # a typed name wins
    create(:provider_common_address, provider: provider, name: "332 Independence Drive Apt 315", address: "332 Independence Drive Apt 315",
           city: "Victoria", state: "TX")
    expect(typed("332 Independence Drive Apt 315").name).to be_nil                                                         # an address saved as a name
    create(:provider_common_address, provider: provider, name: "Thomas Ninke", address: "1907 Lova Drive Apt # 1111", city: "Victoria", state: "TX")
    expect(typed("1907 Lova Drive Apt # 1111").name).to be_nil                                                            # a person, at an apartment
  end
end

RSpec.describe PlaceNaming, "with a saved place already at the address" do
  let(:provider) { create(:provider) }
  let(:admin)    { create(:admin, current_provider: provider) }
  let!(:saved)   { create(:provider_common_address, provider: provider, name: "Warm Springs", address: "102 Medical Dr", city: "Victoria", state: "TX") }

  def typed_copy(name: nil)
    a = TempAddress.new(address: "102 Medical Drive", city: "Victoria", state: "TX", provider: provider, name: name)
    a.save!(validate: false)
    a.update_columns(name: name)   # as booked before saved names were applied
    a
  end

  it "names the trips without making a second saved place" do
    a = typed_copy
    expect { described_class.name_place!(provider: provider, user: admin, address_ids: [a.id], name: "Warm Springs", address_group_id: saved.address_group_id) }
      .not_to change { ProviderCommonAddress.count }
    expect(a.reload.name).to eq "Warm Springs"
  end

  it "backfills unnamed trip addresses that are a saved place, and only blank ones" do
    a = typed_copy; b = typed_copy(name: "Typed by an agent")
    [a, b].each do |x|
      create(:trip, provider: provider, customer: create(:customer, provider: provider), dropoff_address: x,
                    pickup_time: Time.zone.now + 1.day, appointment_time: nil)
    end
    expect(described_class.backfill!(provider)).to eq 1
    expect([a.reload.name, b.reload.name]).to eq ["Warm Springs", "Typed by an agent"]
  end
end

RSpec.describe PlaceNamesController, type: :controller do
  render_views

  context "as an admin" do
    login_admin_as_current_user

    it "shows the list and names a place" do
      group = create(:address_group)
      a = TempAddress.create!(address: "2401 Patterson Drive", city: "Victoria", state: "TX", provider: @current_user.current_provider,
                              the_geom: Address.compute_geom(28.8133, -96.9864))
      create(:trip, provider: @current_user.current_provider, customer: create(:customer, provider: @current_user.current_provider),
                    dropoff_address: a, pickup_time: Time.zone.now + 1.day, appointment_time: nil)
      get :index
      expect(response.body).to include("2401 Patterson Drive", "Look on Google Maps")
      post :create, params: { address_ids: a.id.to_s, name: "Victoria Heart & Vascular", address_group_id: group.id }
      expect(response).to redirect_to(place_names_path)
      expect(a.reload.name).to eq "Victoria Heart & Vascular"
      expect(flash[:named]).to include("Victoria Heart & Vascular")
    end

    it "suggests the businesses Azure Maps lists there" do
      allow(PlaceSearch).to receive(:nearby).and_return([{ name: "Victoria Heart & Vascular", metres: 9 }])
      get :suggest, params: { lat: "28.81", lon: "-96.98" }, format: :json
      expect(JSON.parse(response.body)).to eq [{ "name" => "Victoria Heart & Vascular", "metres" => 9 }]
    end
  end

  context "as someone who may not add saved places" do
    before do
      @request.env["devise.mapping"] = Devise.mappings[:user]
      user = create(:user)
      create(:role, user: user, provider: user.current_provider, level: 0)
      sign_in user
    end

    it "is refused" do
      get :index
      expect(response).not_to have_http_status(:ok)
    end
  end
end
