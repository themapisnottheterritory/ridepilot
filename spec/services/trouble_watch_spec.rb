require "rails_helper"

RSpec.describe TroubleWatch do
  def event(duration_ms, payload)
    instance_double(ActiveSupport::Notifications::Event, duration: duration_ms,
                    payload: { controller: "TripsController", action: "create", trouble_provider_id: 7 }.merge(payload))
  end

  def fake_controller(get: false, alert: nil)
    double(controller_path: "dispatchers", action_name: "schedule", current_provider: double(id: 7),
           request: double(get?: get, head?: false), flash: { alert: alert })
  end

  it "records an action that blew up, with numbers scrubbed and no user" do
    TroubleWatch.action_processed(event(120, exception_object: ActiveRecord::RecordNotFound.new("Couldn't find Trip with 'id'=4521")))
    e = TroubleEvent.last
    expect(e.attributes.slice("kind", "screen", "action", "detail", "provider_id")).to eq(
      "kind" => "error", "screen" => "Trips", "action" => "trips#create",
      "detail" => "ActiveRecord::RecordNotFound: Couldn't find Trip with 'id'=#", "provider_id" => 7)
    expect(TroubleEvent.column_names).not_to include("user_id")
  end

  it "records slow pages, except the ones slow by design" do
    TroubleWatch.action_processed(event(5200, {}))
    TroubleWatch.action_processed(event(900, {}))
    TroubleWatch.action_processed(event(14_000, controller: "RunsController", action: "optimize"))
    expect(TroubleEvent.pluck(:kind, :action, :duration_ms)).to eq [["slow", "trips#create", 5200]]
  end

  it "writes the reasons shown on a save once each, after any rollback" do
    TroubleWatch.watch(fake_controller(alert: "Run 12 is full")) do
      ActiveRecord::Base.transaction do
        TroubleWatch.messages(["Trip schedule does not fit in run schedule", "No driver assigned"])
        TroubleWatch.messages(["Trip schedule does not fit in run schedule"])
        raise ActiveRecord::Rollback
      end
    end
    expect(TroubleEvent.order(:id).pluck(:kind, :screen, :detail)).to eq [
      ["message", "Dispatch", "Trip schedule does not fit in run schedule"],
      ["message", "Dispatch", "No driver assigned"],
      ["message", "Dispatch", "Run # is full"]
    ]
  end

  it "ignores messages on page views and outside requests" do
    TroubleWatch.watch(fake_controller(get: true, alert: "Old alert")) { TroubleWatch.messages(["Seen on a GET"]) }
    TroubleWatch.messages(["From a background job"])
    expect(TroubleEvent.count).to eq 0
  end

  it "lets in system admins and the I.T. addresses only" do
    expect(TroubleWatch.can_view?(double(super_admin?: true, email: "x@y.org"))).to be true
    expect(TroubleWatch.can_view?(double(super_admin?: false, email: "RonaldM@gcrpc.org"))).to be true
    expect(TroubleWatch.can_view?(double(super_admin?: false, email: "kristiek@gcrpc.org"))).to be false
  end

  it "forgets everything after 90 days" do
    TroubleEvent.create!(kind: "slow", screen: "Trips", created_at: 91.days.ago)
    TroubleEvent.create!(kind: "slow", screen: "Trips", created_at: 89.days.ago)
    TroubleEvent.prune!
    expect(TroubleEvent.count).to eq 1
  end
end

RSpec.describe TroubleBoard do
  let(:provider) { create(:provider) }

  it "counts each kind for the period and the one before, day by day, by agency" do
    TroubleEvent.create!(kind: "error", screen: "Trips", action: "trips#create", detail: "Boom", provider_id: provider.id, created_at: 1.hour.ago)
    TroubleEvent.create!(kind: "error", screen: "Trips", action: "trips#create", detail: "Boom", provider_id: provider.id, created_at: 2.days.ago)
    TroubleEvent.create!(kind: "error", screen: "Runs", action: "runs#show", detail: "Other", provider_id: provider.id + 1, created_at: 1.hour.ago)
    TroubleEvent.create!(kind: "error", screen: "Trips", action: "trips#create", detail: "Boom", provider_id: provider.id, created_at: 10.days.ago)
    board = described_class.new(days: 7, provider_id: provider.id)
    s = board.summary["error"]
    expect([s[:count], s[:previous], s[:daily].size, s[:daily].last]).to eq [2, 1, 7, 1]
    expect(board.errors.map { |r| [r[:screen], r[:detail], r[:count]] }).to eq [["Trips", "Boom", 2]]
    expect(described_class.new(days: 7).summary["error"][:count]).to eq 3
  end

  it "groups Ask RidePilot misses by screen, without names" do
    user = create(:user)
    HelpQuestion.create!(user: user, provider: provider, page_path: "/en/trips/new", question: "How do I clone?", answer: "I'm not sure.")
    HelpQuestion.create!(user: user, provider: provider, page_path: "/en/trips", question: "Where is fare?", answer: "Here.", helpful: false)
    HelpQuestion.create!(user: user, provider: provider, page_path: "/en/runs", question: "Fine", answer: "Open Runs.", helpful: true)
    misses = described_class.new(days: 7).help_misses
    expect(misses.map { |g| [g[:screen], g[:count]] }).to eq [["Trips", 2]]
    expect(misses.first[:questions].map { |q| q[:why] }).to contain_exactly("unsure", "thumbs down")
    expect(misses.first[:questions].first.keys).not_to include(:user)
  end
end

RSpec.describe TroubleBoardController, type: :controller do
  render_views
  login_admin_as_current_user

  it "shows the board to I.T." do
    allow_any_instance_of(User).to receive(:super_admin?).and_return(true)
    TroubleEvent.create!(kind: "error", screen: "Trips", action: "trips#create", detail: "ActiveRecord::RecordInvalid: Nope", created_at: 1.hour.ago)
    get :index, params: { days: 30 }
    expect(response.status).to eq 200
    expect(response.body).to include("Trouble board", "RecordInvalid", "Nope", "tb-bars")
  end

  it "keeps everyone else out" do
    allow_any_instance_of(User).to receive(:super_admin?).and_return(false)
    allow_any_instance_of(User).to receive(:email).and_return("someone@gcrpc.org")
    get :index
    expect(response.status).to eq 403
  end
end
