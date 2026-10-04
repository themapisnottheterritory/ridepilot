require "rails_helper"

# The server clock is UTC: from 7 PM Central (6 PM in winter) Date.today is already
# tomorrow, and a driver's run vanished from the tablet (found 2026-10-03).
RSpec.describe Api::V1::Driver::RunsController, type: :controller do
  include ActiveSupport::Testing::TimeHelpers
  let(:driver) { create(:driver) }

  before do
    user = driver.user
    user.update_column(:authentication_token, "tok-#{SecureRandom.hex(8)}") if user.authentication_token.blank?
    request.headers.merge!("X-User-Username" => user.username, "X-User-Token" => user.authentication_token)
  end

  it "still lists today's run at 7:30 PM Central" do
    travel_to Time.find_zone("Central Time (US & Canada)").parse("2026-10-03 19:30") do
      run = create(:run, driver: driver, provider: driver.provider, date: Date.new(2026, 10, 3),
                         scheduled_start_time: Time.zone.parse("2026-10-03 15:00"), scheduled_end_time: Time.zone.parse("2026-10-03 21:00"))
      trip = create(:trip, provider: run.provider, run: run, pickup_time: Time.zone.parse("2026-10-03 16:00"), appointment_time: Time.zone.parse("2026-10-03 16:30"))
      run.reset_itineraries
      run.update_column(:manifest_order, run.sorted_itineraries.map(&:itin_id))
      run.publish_manifest!
      get :index
      ids = JSON.parse(response.body)["data"].map { |r| (r["id"] || r.dig("attributes", "id")).to_i }
      expect(ids).to include(run.id)
    end
  end
end
