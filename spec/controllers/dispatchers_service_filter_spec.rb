require "rails_helper"

# CSRs (2026-09-30): Dispatch listed 27 fixed-route runs among the 28
# demand-response ones, and names sorted UDR1, UDR10, UDR2.
RSpec.describe DispatchersController, "runs shown", type: :controller do
  login_admin_as_current_user
  let(:provider) { @current_user.current_provider }

  def run(name, mode)
    r = build(:run, provider: provider, name: name, date: Date.current, service_mode: mode)
    r.save!(validate: false)
    r
  end

  it "shows demand-response runs by default, in natural name order" do
    %w[UDR10 UDR2 UDR1 DeWitt1].each { |n| run(n, "demand_response") }
    run("Gold", "fixed_route")
    get :index, params: { run_trip_filters: { run_trip_day: Date.current.strftime("%a %b %d, %Y") } }
    expect(assigns(:runs).map(&:name)).to eq %w[DeWitt1 UDR1 UDR2 UDR10]
  end

  it "remembers the person's choice to see fixed-route or all runs, and never offers a fixed-route run for a trip" do
    run("UDR1", "demand_response"); run("Gold", "fixed_route")
    get :index, params: { run_trip_filters: { run_trip_day: Date.current.strftime("%a %b %d, %Y"), dispatch_service_mode: "all" } }
    expect(assigns(:runs).map(&:name)).to eq %w[Gold UDR1]
    expect(assigns(:schedule_options).map(&:last)).to include("UDR1")
    expect(assigns(:schedule_options).map(&:last)).not_to include("Gold")
    get :index
    expect(assigns(:runs).map(&:name)).to eq %w[Gold UDR1]
    get :index, params: { run_trip_filters: { dispatch_service_mode: "nonsense" } }
    expect(assigns(:runs).map(&:name)).to eq %w[Gold UDR1]   # an unknown value changes nothing
  end
end
