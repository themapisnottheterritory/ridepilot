require "rails_helper"

RSpec.describe DispatchInbox do
  let(:run)    { create(:run) }
  let(:driver) { run.driver }
  let(:staff)  { create(:role, provider: run.provider, level: Role::EDITOR_LEVEL).user }
  let(:inbox)  { DispatchInbox.new(run.provider_id) }

  def say(sender, body) = RoutineMessage.create!(provider: run.provider, driver: driver, run: run, sender: sender, body: body)

  it "counts only drivers' messages not yet seen, and one dispatcher seeing them clears them for all" do
    say(driver.user, "Rider not home")
    say(driver.user, "Calling now")
    say(staff, "OK")
    expect(inbox.unhandled_count).to eq 2
    expect { inbox.handle!(driver.id, staff) }
      .to have_broadcasted_to("dispatch_#{run.provider_id}").with(hash_including(kind: "handled", driver_id: driver.id, by: staff.display_name, unhandled: 0))
    expect(inbox.unhandled_count).to eq 0
    expect(inbox.recent.map(&:handled_by)).to all(eq staff)
  end
end
