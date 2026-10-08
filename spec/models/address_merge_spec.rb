require "rails_helper"

RSpec.describe Address, "#replace_with!" do
  let(:old_place) { create(:provider_common_address, name: "Gulf Bend Center", address: "1408 Melrose") }
  let(:new_place) { create(:provider_common_address, name: "Gulf Bend Center", address: "6502 Nursery Dr") }

  it "moves trips, standing trips and run stops, then deletes the old place" do
    trip = create(:trip, dropoff_address: old_place)
    standing = create(:repeating_trip, dropoff_address: old_place)
    itin = Itinerary.new(trip: trip, address_id: old_place.id, leg_flag: 2)
    itin.save!(validate: false)

    expect(old_place.replace_with!(new_place.id)).to eq new_place
    expect(trip.reload.dropoff_address_id).to eq new_place.id
    expect(standing.reload.dropoff_address_id).to eq new_place.id
    expect(itin.reload.address_id).to eq new_place.id
    expect(Address.find_by(id: old_place.id)).to be_nil
  end

  it "won't merge a place into itself or into nothing" do
    expect(old_place.replace_with!(old_place.id)).to be false
    expect(old_place.replace_with!("")).to be false
    expect(Address.find_by(id: old_place.id)).to be_present
  end
end
