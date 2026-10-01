require "rails_helper"

RSpec.describe ChatWorker do
  let(:run)    { create(:run) }
  let(:driver) { run.driver }
  let(:staff)  { create(:role, provider: run.provider, level: Role::EDITOR_LEVEL).user }

  def say(sender) = RoutineMessage.create!(provider: run.provider, driver: driver, run: run, sender: sender, body: "hello")

  it "sends the tablet the message under 'message' (what its chat page reads) as well as at the top level" do
    m = say(staff)
    expect { ChatWorker.new.perform(m.id) }
      .to have_broadcasted_to("chat_channel_#{run.provider_id}_#{driver.id}")
      .with(hash_including(action: "CreateMessage", id: m.id, body: "hello", message: hash_including(id: m.id, body: "hello")))
  end

  it "tells the dispatch desk when a driver writes, and not when a dispatcher does" do
    from_driver = say(driver.user)
    expect { ChatWorker.new.perform(from_driver.id) }
      .to have_broadcasted_to("dispatch_#{run.provider_id}").with(hash_including(kind: "chat", run_name: run.name, unhandled: 1))
    expect { ChatWorker.new.perform(say(staff).id) }.not_to have_broadcasted_to("dispatch_#{run.provider_id}")
  end
end
