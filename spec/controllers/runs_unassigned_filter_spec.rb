require "rails_helper"

# The runs list can be narrowed to what still has nobody, or no bus, on it.
RSpec.describe RunsController, type: :controller do
  render_views
  login_admin_as_current_user

  before do
    @provider = @current_user.current_provider
    route = FixedRoute.create!(provider: @provider, name: "Blue", color: "0000FF")
    @bare = Run.new(provider: @provider, name: "Blue", service_mode: "fixed_route", fixed_route: route, date: Date.today,
                    scheduled_start_time: Time.zone.parse("07:30"), scheduled_end_time: Time.zone.parse("17:00"))
    @bare.save!(validate: false)
    driver = create(:driver, provider: @provider)
    vehicle = build(:vehicle, provider: @provider); vehicle.save!(validate: false)
    @staffed = Run.new(provider: @provider, name: "Gold", service_mode: "fixed_route", fixed_route: route, date: Date.today,
                       driver: driver, vehicle: vehicle, scheduled_start_time: Time.zone.parse("07:30"), scheduled_end_time: Time.zone.parse("17:00"))
    @staffed.save!(validate: false)
  end

  it "lists only runs with no driver when asked" do
    get :index, params: { run_filters: { start: Date.today.strftime("%m/%d/%Y"), end: Date.today.strftime("%m/%d/%Y"), driver_id: "unassigned" } }
    expect(response).to be_successful
    expect(assigns(:runs).map(&:id)).to eq [@bare.id]
    expect(response.body).to include("No driver assigned")
  end

  it "lists only runs with no bus when asked, and everything otherwise" do
    get :index, params: { run_filters: { start: Date.today.strftime("%m/%d/%Y"), end: Date.today.strftime("%m/%d/%Y"), vehicle_id: "unassigned" } }
    expect(assigns(:runs).map(&:id)).to eq [@bare.id]
    get :index, params: { run_filters: { start: Date.today.strftime("%m/%d/%Y"), end: Date.today.strftime("%m/%d/%Y"), vehicle_id: "", driver_id: "" } }
    expect(assigns(:runs).map(&:id).sort).to eq [@bare.id, @staffed.id].sort
  end
end
