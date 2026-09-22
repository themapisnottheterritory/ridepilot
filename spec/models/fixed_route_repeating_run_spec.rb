require "rails_helper"

# Fixed-route blocks are scheduled by route; the driver and bus can be filled
# in later (or confirmed on the tablet). Demand-response runs still need a bus.
RSpec.describe RepeatingRun, "fixed route" do
  let(:provider) { create(:provider) }
  let(:route)    { FixedRoute.create!(provider: provider, name: "Blue", color: "0000FF") }

  def block(attrs = {})
    rr = RepeatingRun.new({ provider: provider, name: "Blue", service_mode: "fixed_route", fixed_route: route,
      scheduled_start_time: Time.zone.parse("07:30"), scheduled_end_time: Time.zone.parse("17:00"),
      start_date: Date.today, paid: true }.merge(attrs))
    %w[monday tuesday wednesday thursday friday].each { |d| rr.send("repeats_#{d}s=", true) }
    rr
  end

  it "saves without a driver or a bus and generates the daily runs" do
    rr = block
    expect(rr.save).to be(true), rr.errors.full_messages.join("; ")
    expect(rr.runs.count).to be > 0
    run = rr.runs.first
    expect(run.service_mode).to eq "fixed_route"
    expect(run.fixed_route).to eq route
    expect(run.driver).to be_nil
    expect(run.vehicle).to be_nil
    expect(run.scheduled_start_time_string).to eq "07:30:00"
  end

  it "still requires a bus for a demand-response block" do
    rr = block(service_mode: "demand_response", fixed_route: nil)
    expect(rr.save).to be false
    expect(rr.errors[:vehicle]).to be_present
  end
end
