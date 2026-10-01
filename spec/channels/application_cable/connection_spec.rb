require "rails_helper"

# Driver tablets open the live-update socket with ?username=&token= (the
# Demand Response app) or ?username=&authentication_token= (older clients).
# Rejecting the first kept every tablet reconnecting every 3 s and cut them
# off from emergency alerts and manifest pushes (2026-10-01).
RSpec.describe ApplicationCable::Connection, type: :channel do
  let(:user) { create(:driver).user }

  before { user.update_column(:authentication_token, "tok-#{SecureRandom.hex(8)}") }

  it "accepts a tablet that sends token" do
    connect "/cable?username=#{user.username}&token=#{user.authentication_token}"
    expect(connection.current_user).to eq user
  end

  it "accepts a client that sends authentication_token" do
    connect "/cable?username=#{user.username}&authentication_token=#{user.authentication_token}"
    expect(connection.current_user).to eq user
  end

  it "rejects a wrong token" do
    expect { connect "/cable?username=#{user.username}&token=wrong" }.to have_rejected_connection
  end

  it "rejects a missing token, even for a user with none set" do
    user.update_column(:authentication_token, nil)
    expect { connect "/cable?username=#{user.username}" }.to have_rejected_connection
  end
end
