require "rails_helper"

# Who may listen to which live stream (2026-10-01): office staff to their own
# agencies, a driver's tablet to its own driver and runs.
RSpec.describe "channel scoping", type: :channel do
  let(:run)    { create(:run).tap { |r| r.driver.update_column(:provider_id, r.provider_id) } }   # the factory gives them different agencies
  let(:driver) { run.driver }
  let(:other)  { create(:driver, provider: run.provider) }
  let(:staff)  { create(:role, provider: run.provider, level: Role::EDITOR_LEVEL).user }
  let(:outsider) { create(:role, provider: create(:provider), level: Role::ADMIN_LEVEL).user }

  describe DispatchChannel, type: :channel do
    it "lets the agency's staff listen" do
      stub_connection current_user: staff, view_only: nil
      subscribe provider_id: run.provider_id
      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_from("dispatch_#{run.provider_id}")
    end

    it "turns away a driver's tablet and another agency's staff" do
      [driver.user, outsider].each do |u|
        stub_connection current_user: u, view_only: nil
        subscribe provider_id: run.provider_id
        expect(subscription).to be_rejected
      end
    end
  end

  describe ChatChannel, type: :channel do
    it "lets a driver follow their own conversation, not another driver's" do
      stub_connection current_user: driver.user, view_only: nil
      subscribe provider_id: run.provider_id, driver_id: driver.id
      expect(subscription).to be_confirmed
      subscribe provider_id: run.provider_id, driver_id: other.id
      expect(subscription).to be_rejected
    end

    it "lets staff follow any driver of their agency" do
      stub_connection current_user: staff, view_only: nil
      subscribe provider_id: run.provider_id, driver_id: other.id
      expect(subscription).to be_confirmed
    end
  end

  describe ManifestChannel, type: :channel do
    it "lets a driver follow only their own run" do
      stub_connection current_user: other.user, view_only: nil
      subscribe run_id: run.id
      expect(subscription).to be_rejected
      stub_connection current_user: driver.user, view_only: nil
      subscribe run_id: run.id
      expect(subscription).to be_confirmed
    end
  end

  describe AlertChannel, type: :channel do
    it "records Got it! as whoever pressed it, once" do
      alert = EmergencyAlert.create!(provider: run.provider, driver: driver, run: run, sender: driver.user)
      stub_connection current_user: staff, view_only: nil
      subscribe provider_id: run.provider_id
      perform :dismiss, id: alert.id, reader_id: outsider.id
      expect(alert.reload.reader).to eq staff
    end
  end
end
