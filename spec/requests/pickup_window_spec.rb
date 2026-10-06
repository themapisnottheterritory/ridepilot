require "rails_helper"

# Pick-up window and no-show rules (PickupWindow), 2026-10-06: Robert Gardner's
# tablet showed a drop-off before its pick-up, and no-shows were being recorded
# before riders' booked times. FTA Circular C 4710.1 §8.4.5, §8.5.3, §8.5.4.
RSpec.describe "pick-up window and no-shows", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers
  let(:run)     { create(:run, date: Date.current).tap { |r| r.driver.update_column(:provider_id, r.provider_id) } }
  let(:provider) { run.provider }
  let(:driver)  { run.driver }
  let(:booked)  { Time.zone.now.change(sec: 0) + 2.hours }
  let(:trip)    { create(:trip, provider: provider, run: run, pickup_time: booked, appointment_time: nil, early_pickup_allowed: false) }
  let!(:pickup) { create(:itinerary, run: run, trip: trip, leg_flag: 1, status_code: 0) }
  let(:tablet) do
    driver.user.ensure_authentication_token; driver.user.save!
    { "X-User-Username" => driver.user.username, "X-User-Token" => driver.user.authentication_token }
  end

  describe "the window" do
    it "follows the agency's settings: 0/+30 and a 5-minute wait by default" do
      w = PickupWindow.for(trip)
      expect([w.opens, w.closes, w.no_show_from]).to eq [booked, booked + 30.minutes, booked + 5.minutes]
      expect(w.earliest_boarding).to eq booked
    end

    it "lets a rider who agreed board up to the early allowance before the window" do
      trip.update_column(:early_pickup_allowed, true)
      expect(PickupWindow.for(trip.reload).earliest_boarding).to eq booked - 15.minutes
    end

    it "marks new trips early-OK only when someone ticks it" do
      expect(Trip.new(provider: provider).early_pickup_allowed).to be false
    end

    it "refuses an agency setting longer than FTA allows, and says why" do
      provider.pickup_window_early_min = 15
      provider.pickup_window_late_min = 30
      expect(provider).not_to be_valid
      expect(provider.errors.full_messages.join).to include("45-minute pick-up window is too long", "FTA Circular C 4710.1 §8.4.5")
    end
  end

  describe "the tablet's No Show" do
    it "is refused before the window opens plus the wait, with the reason, and nothing is recorded" do
      put "/api/v1/itineraries/#{pickup.id}/noshow", params: { at: (booked - 40.minutes).iso8601 }, headers: tablet, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body).dig("error", "message")).to include("Too early for a no-show", "§8.5.3")
      expect(trip.reload.trip_result).to be_nil
      expect(pickup.reload.finish_time).to be_nil
    end

    it "is refused when the bus came after the window closed: a missed trip" do
      pickup.update_column(:arrival_time, booked + 40.minutes)
      put "/api/v1/itineraries/#{pickup.id}/noshow", params: { at: (booked + 46.minutes).iso8601 }, headers: tablet, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body).dig("error", "message")).to include("missed trip, not a no-show", "§8.5.4")
    end

    it "is recorded once the window has opened and the driver has waited" do
      allow(ChatWorker).to receive(:perform_async)   # the note to dispatch goes through Sidekiq
      TripResult.find_by(code: "NS") || create(:trip_result, code: "NS", name: "No-show")
      travel_to(booked + 6.minutes) do
        put "/api/v1/itineraries/#{pickup.id}/noshow", headers: tablet, as: :json
      end
      expect(response).to be_successful, response.body[0, 400]
      expect(trip.reload.trip_result.code).to eq "NS"
    end

    it "sends the tablet the window and when a no-show may be recorded" do
      get "/api/v1/itineraries/#{pickup.id}", headers: tablet
      w = JSON.parse(response.body).dig("data", "attributes", "pickup_window") || JSON.parse(response.body).dig("data", "data", "attributes", "pickup_window")
      expect(Time.zone.parse(w["no_show_from"])).to eq booked + 5.minutes
    end
  end

  describe "Dispatch" do
    let(:staff) { create(:role, provider: provider, level: Role::EDITOR_LEVEL).user }

    it "can't set No-show before the window opens plus the wait, and is told why" do
      staff.update!(current_provider: provider); sign_in staff
      ns = TripResult.find_by(code: "NS") || create(:trip_result, code: "NS", name: "No-show")
      patch "/en/trips/#{trip.id}/change_result", params: { trip_id: trip.id, trip: { trip_result_id: ns.id } }, xhr: true
      expect(response.body).to include("Too early for a no-show")
      expect(trip.reload.trip_result_id).to be_nil
    end
  end

  describe "the live estimate" do
    it "has the bus wait at a pick-up for the window, and estimates the drop-off from then" do
      dropoff = create(:itinerary, run: run, trip: trip, leg_flag: 2, status_code: 0)
      [pickup, dropoff].each_with_index { |i, n| PublicItinerary.create!(run: run, itinerary: i, sequence: n) }
      GpsLocation.create!(run_id: run.id, provider_id: provider.id, latitude: 28.8, longitude: -97.0, log_time: Time.current)
      allow_any_instance_of(Address).to receive(:latitude).and_return(28.8)
      allow_any_instance_of(Address).to receive(:longitude).and_return(-97.0)
      est = RunEtaEstimator.new(run)
      allow(est).to receive(:osrm_leg_durations).and_return([600, 600])   # 10 min to the pick-up, 10 to the drop-off
      est.update!
      expect(trip.reload.estimated_pickup_time).to be_within(1.second).of(booked)          # not 10 minutes from now
      expect(PublicItinerary.find_by(itinerary_id: dropoff.id).eta).to be > booked + 10.minutes
    end
  end
end
