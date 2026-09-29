require "rails_helper"

RSpec.describe MobilityIconHelper, type: :helper do
  def trip_with(*devices)
    trip = build(:trip)
    allow(trip).to receive(:ridership_mobilities).and_return(
      devices.map { |name, capacity| double(capacity: capacity || 1, mobility: double(name: name)) })
    trip
  end

  it "shows a wheelchair for wheelchairs and scooters, naming them on hover" do
    html = helper.mobility_icon(trip_with(["Wheelchair - Can Transfer"], ["Ambulatory"]))
    expect(html).to include("fa-wheelchair", 'title="Wheelchair - Can Transfer"')
  end

  it "shows a person with a cane for a walker" do
    expect(helper.mobility_icon(trip_with(["Walker"]))).to include("fa-blind", 'title="Walker"')
  end

  it "shows nothing for ambulatory, unknown, or a device with no count" do
    expect(helper.mobility_icon(trip_with(["Ambulatory"], ["Unknown"], ["Wheelchair", 0]))).to be_blank
  end
end
