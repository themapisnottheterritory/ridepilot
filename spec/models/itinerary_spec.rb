require 'rails_helper'

RSpec.describe Itinerary, type: :model do
  # Launch morning 2026-10-01: stops were built with no status and the driver
  # tablet, which offers Depart only on a Pending stop, could not start any.
  describe "status" do
    it "starts Pending when a run builds its stops" do
      run = create(:run)
      itin = run.build_itinerary(Time.current, nil, nil, 1)
      itin.save!(validate: false)
      expect(itin.reload.status_code).to eq Itinerary::STATUS_PENDING
    end

    it "is saved as Pending when something clears it" do
      itin = create(:itinerary)
      itin.update_column(:status_code, nil)
      itin.reload.save!(validate: false)
      expect(itin.reload.status_code).to eq Itinerary::STATUS_PENDING
    end

    it "goes back to Pending on reset!" do
      itin = create(:itinerary, status_code: Itinerary::STATUS_IN_PROGRESS, departure_time: Time.current)
      itin.reset!
      expect(itin.reload.status_code).to eq Itinerary::STATUS_PENDING
      expect(itin.departure_time).to be_nil
    end

    it "reads as Pending on the tablet for an old stop with none" do
      itin = create(:itinerary)
      itin.update_column(:status_code, nil)
      json = ItinerarySerializer.new(itin.reload).serializable_hash
      expect(json[:data][:attributes][:status_code]).to eq Itinerary::STATUS_PENDING
    end
  end
end
