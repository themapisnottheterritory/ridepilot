require "rails_helper"

# "Occupancy 0" on every stop (2026-09-29): Dispatch now measures a run
# against the bus's own seats and wheelchair spots, like Optimize Route.
RSpec.describe DispatchHelper, "run_vehicle_capacities", type: :helper do
  def vehicle(seats, wheelchairs, type = nil)
    double(seating_capacity: seats, mobility_device_accommodations: wheelchairs, vehicle_type: type)
  end

  it "uses the vehicle's own seats and wheelchair spots" do
    # capacity types are shared by all agencies (no provider), so skip the provider validation
    seat = CapacityType.new(name: "Seat"); seat.save!(validate: false)
    wc = CapacityType.new(name: "Wheelchair position"); wc.save!(validate: false)
    run = double(vehicle: vehicle(12, 2))
    expect(helper.run_vehicle_capacities(run)).to eq [{ seat.id => 12, wc.id => 2 }]
  end

  it "falls back to the vehicle type's configurations until there's a Seat type" do
    type = double(vehicle_capacity_configurations: [double(vehicle_capacities: double(pluck: [[9, 16]]))])
    run = double(vehicle: vehicle(12, 2, type))
    expect(helper.run_vehicle_capacities(run)).to eq [{ 9 => 16 }]
  end

  it "has nothing to measure against without a vehicle" do
    expect(helper.run_vehicle_capacities(double(vehicle: nil))).to be_nil
  end
end
