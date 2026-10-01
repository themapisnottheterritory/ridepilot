require "rails_helper"

# A view-only tablet (TabletView) connects as the driver, flagged view only.
RSpec.describe ApplicationCable::Connection, type: :channel do
  let(:driver) { create(:driver) }
  let(:office) { create(:user) }

  it "takes a view key as the driver, view only" do
    key = TabletView.issue(office, driver.user)
    connect "/cable", params: { username: driver.user.username, token: key }
    expect(connection.current_user).to eq driver.user
    expect(connection.view_only).to be true
  end

  it "turns away a view key sent under another username" do
    key = TabletView.issue(office, driver.user)
    expect { connect "/cable", params: { username: "someoneelse", token: key } }.to have_rejected_connection
  end

  it "leaves the driver's own connection able to act" do
    driver.user.ensure_authentication_token
    driver.user.save!
    connect "/cable", params: { username: driver.user.username, token: driver.user.authentication_token }
    expect(connection.view_only).to be_falsey
  end
end
