require "rails_helper"

# 2026-10-01: "Will call ready", the no-show note to dispatch, and who has
# seen what, on both sides.
RSpec.describe "will call ready, no-shows and seen receipts", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:run)    { create(:run).tap { |r| r.driver.update_column(:provider_id, r.provider_id) } }
  let(:driver) { run.driver }
  let(:staff)  { create(:role, provider: run.provider, level: Role::EDITOR_LEVEL).user }
  let(:trip)   { create(:trip, provider: run.provider, run: run, will_call: true) }
  let!(:pickup) { create(:itinerary, run: run, trip: trip, leg_flag: 1, status_code: 0) }
  let(:tablet) do
    driver.user.ensure_authentication_token; driver.user.save!
    { "X-User-Username" => driver.user.username, "X-User-Token" => driver.user.authentication_token }
  end

  it "Ready sends the driver a message tied to the trip and its pickup stop, and records when" do
    staff.update!(current_provider: run.provider); sign_in staff
    post "/en/trips/#{trip.id}/will_call_ready", xhr: true
    m = RoutineMessage.last
    expect(m).to have_attributes(trip_id: trip.id, driver_id: driver.id, run_id: run.id, sender_id: staff.id)
    expect { ChatWorker.new.perform(m.id) }   # Sidekiq sends it; jobs don't run by themselves in specs
      .to have_broadcasted_to("chat_channel_#{run.provider_id}_#{driver.id}")
      .with(hash_including(action: "CreateMessage", trip_id: trip.id, itinerary_id: pickup.id))
    expect(m.body).to start_with("Will call ready: #{trip.customer.name}")
    expect(trip.reload.will_call_ready_at).to be_present
    expect(trip.will_call_ready_by_id).to eq staff.id
  end

  it "says why when the trip's run has no driver" do
    staff.update!(current_provider: run.provider); sign_in staff
    run.update_column(:driver_id, nil)
    post "/en/trips/#{trip.id}/will_call_ready", xhr: true
    expect(response.body).to include("has no driver")
    expect(trip.reload.will_call_ready_at).to be_nil
  end

  it "a driver's no-show goes to the dispatch inbox" do
    put "/api/v1/itineraries/#{pickup.id}/noshow", headers: tablet, as: :json
    m = RoutineMessage.last
    expect(m).to have_attributes(trip_id: trip.id, sender_id: driver.user_id)
    expect(m.body).to start_with("No-show: #{trip.customer.name}")
    expect { ChatWorker.new.perform(m.id) }.to have_broadcasted_to("dispatch_#{run.provider_id}").with(hash_including(kind: "chat"))
  end

  it "tells the tablet who at dispatch saw the driver's messages" do
    RoutineMessage.create!(provider: run.provider, driver: driver, run: run, sender: driver.user, body: "Running late")
    expect { DispatchInbox.new(run.provider_id).handle!(driver.id, staff) }
      .to have_broadcasted_to("chat_channel_#{run.provider_id}_#{driver.id}").with(hash_including(action: "SeenByDispatch", by: staff.display_name))
  end

  it "tells the dispatcher's chat window when the driver read a message" do
    m = RoutineMessage.create!(provider: run.provider, driver: driver, run: run, sender: staff, body: "Pick up 3:00")
    expect { post "/api/v1/messages/read_message", params: { message_id: m.id }, headers: tablet, as: :json }
      .to have_broadcasted_to("chat_channel_#{run.provider_id}_#{driver.id}").with(hash_including(action: "SeenByDriver", message_id: m.id))
  end

  it "gives the tablet's history the trip and the stop to go to" do
    m = trip.will_call_ready!(staff)
    get "/api/v1/messages/chats", headers: tablet
    attrs = JSON.parse(response.body)["data"].find { |d| d["id"].to_s == m.id.to_s }["attributes"]
    expect(attrs).to include("trip_id" => trip.id, "itinerary_id" => pickup.id, "run_id" => run.id)
  end
end
