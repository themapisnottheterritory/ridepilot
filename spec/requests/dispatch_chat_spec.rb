require "rails_helper"

# The CAD chat popup and the tablet's message API (2026-10-01 fixes).
RSpec.describe "dispatcher and driver chat", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:run)    { create(:run).tap { |r| r.driver.update_column(:provider_id, r.provider_id) } }
  let(:driver) { run.driver }
  let(:staff)  { create(:role, provider: run.provider, level: Role::EDITOR_LEVEL).user }

  def from_driver(body = "Rider not home") = RoutineMessage.create!(provider: run.provider, driver: driver, run: run, sender: driver.user, body: body)

  describe "the CAD chat popup" do
    before { staff.update!(current_provider: run.provider); sign_in staff }

    it "marks the driver's messages seen by whoever opened it" do
      m = from_driver
      get "/en/driver_chat", params: { run_id: run.id }
      expect(response).to be_successful
      expect(m.reload.handled_by).to eq staff
    end

    it "says so instead of crashing for a run with no driver" do
      run.update_column(:driver_id, nil)
      get "/en/driver_chat", params: { run_id: run.id }
      expect(response.body).to include("no driver")
    end

    it "records a read as the signed-in dispatcher, whatever the page sends" do
      m = from_driver
      post "/en/chat/read", params: { message_id: m.id, read_by_id: 999_999 }
      expect(ChatReadReceipt.last.read_by_id).to eq staff.id
    end

    it "puts the inbox in the header and the desk on every page, counting what's unseen" do
      from_driver
      get "/en/cad_avl"
      expect(response.body).to include("window.DispatchDesk", "dd-toasts")
      get "/"
      follow_redirect! while response.redirect?
      expect(response.body).to include('id="dispatch-inbox-link"', '<span class="dd-count">1</span>')
    end

    it "lists the inbox for the header" do
      from_driver("Running 10 late")
      get "/en/dispatch_inbox"
      expect(response.body).to include("Running 10 late", run.name)
    end
  end

  describe "the tablet's message API" do
    let(:headers) do
      driver.user.ensure_authentication_token; driver.user.save!
      { "X-User-Username" => driver.user.username, "X-User-Token" => driver.user.authentication_token }
    end

    it "saves a message the tablet sent without a run, on the driver's run today" do
      post "/api/v1/messages/send_message", params: { body: "On my way" }, headers: headers, as: :json
      expect(RoutineMessage.last).to have_attributes(body: "On my way", run_id: run.id, driver_id: driver.id)
    end

    it "never files a message on another driver's run" do
      other_run = create(:run, provider: run.provider)
      post "/api/v1/messages/send_message", params: { body: "x", run_id: other_run.id }, headers: headers, as: :json
      expect(RoutineMessage.last.run_id).to eq run.id
    end
  end
end
