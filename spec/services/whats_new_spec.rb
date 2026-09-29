require "rails_helper"

RSpec.describe WhatsNew do
  let(:file) { Tempfile.new(["whats_new", ".yml"]) }
  let(:gcrpc) { create(:provider) }
  let(:county) { create(:provider) }
  let(:user) { create(:user, current_provider: gcrpc) }

  before do
    file.write(<<~YAML); file.flush
      - added: "#{(Time.zone.now - 1.hour).strftime('%Y-%m-%d %H:%M')}"
        title: For everyone
        body: Click **Dispatch**.
      - added: "#{(Time.zone.now - 2.hours).strftime('%Y-%m-%d %H:%M')}"
        title: Admins only
        for: admins
        body: Admin thing.
      - added: "#{(Time.zone.now - 3.hours).strftime('%Y-%m-%d %H:%M')}"
        title: GCRPC only
        providers: [#{gcrpc.id}]
        body: Buses.
      - added: "#{(Time.zone.now - 100.days).strftime('%Y-%m-%d %H:%M')}"
        title: Long ago
        body: Old news.
    YAML
    stub_const("WhatsNew::FILE", Pathname.new(file.path))
  end

  it "shows each note only to its audience" do
    allow(user).to receive(:admin?).and_return(false)
    expect(described_class.for(user, gcrpc).map(&:title)).to eq ["For everyone", "GCRPC only", "Long ago"]
    expect(described_class.for(user, county).map(&:title)).to eq ["For everyone", "Long ago"]
    allow(user).to receive(:admin?).and_return(true)
    expect(described_class.for(user, county).map(&:title)).to eq ["For everyone", "Admins only", "Long ago"]
  end

  it "counts notes added since the user last looked; two weeks for someone who never has" do
    allow(user).to receive(:admin?).and_return(true)
    expect(described_class.unseen_count(user, gcrpc)).to eq 3
    user.whats_new_seen_at = Time.zone.now - 150.minutes
    expect(described_class.unseen_count(user, gcrpc)).to eq 2
    user.whats_new_seen_at = Time.zone.now
    expect(described_class.unseen_count(user, gcrpc)).to eq 0
  end

  it "gives Ask RidePilot the recent notes" do
    text = described_class.guide_text
    expect(text).to include("## For everyone", "Click **Dispatch**.", "## Admins only")
    expect(text).not_to include("Long ago")
  end

  it "reads the real notes file" do
    stub_const("WhatsNew::FILE", Rails.root.join("config", "whats_new.yml"))
    notes = described_class.notes
    expect(notes).not_to be_empty
    expect(notes.map(&:added)).to eq notes.map(&:added).sort.reverse
    expect(notes).to all(have_attributes(title: be_present, body: be_present))
  end
end

RSpec.describe WhatsNewController, type: :controller do
  login_admin_as_current_user

  it "lists the notes and marks them seen" do
    get :index
    expect(response.status).to eq 200
    expect(@current_user.reload.whats_new_seen_at).to be_within(1.minute).of(Time.current)
    expect(WhatsNew.unseen_count(@current_user, @current_user.current_provider)).to eq 0
  end
end
