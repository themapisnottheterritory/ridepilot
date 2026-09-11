require "rails_helper"

RSpec.describe Vehicle, "optional associations" do
  it "saves without a default driver, garage address or maintenance schedule type, as the whole fleet is recorded" do
    provider = create(:provider)
    type = VehicleType.create!(name: "Bus (16 Passenger)", provider: provider)
    v = Vehicle.new(provider: provider, vehicle_type: type, name: "1733", make: "Ford", model: "E450 Eldorado Aerotech 240", year: 2019, wheelchair_lift: true)
    expect(v).to be_valid
    expect(v.save).to be true
    expect(v.reload.wheelchair_lift).to be true
  end
end
