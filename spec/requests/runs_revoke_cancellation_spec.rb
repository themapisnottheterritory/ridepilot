require "rails_helper"

# Runs page, Apply Action -> Revoke cancellation (2026-10-01).
RSpec.describe "Runs page: revoke cancellation", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:staff) { create(:role, level: Role::ADMIN_LEVEL).user }
  let(:run)   { create(:run, provider: staff.current_provider, cancelled: true, date: Date.current + 3) }

  before { sign_in staff }

  it "offers it in the menu" do
    run
    get "/en/runs"
    expect(response).to be_successful
    expect(response.body).to include('data-run-batch-action="revoke_cancellation"', "Revoke cancellation", "revoke-cancellation-multiple-runs")
  end

  it "takes the Cancelled mark off the selected runs and says what happened" do
    patch "/en/runs/revoke_cancellation_multiple", params: { revoke_cancellation_multiple_runs: { run_ids: run.id.to_s } }
    expect(response).to redirect_to(runs_path)
    expect(flash[:notice]).to include("Cancellation revoked on 1 run")
    expect(run.reload.cancelled).to be false
  end

  it "leaves another agency's runs alone" do
    theirs = create(:run, cancelled: true)
    patch "/en/runs/revoke_cancellation_multiple", params: { revoke_cancellation_multiple_runs: { run_ids: theirs.id.to_s } }
    expect(theirs.reload.cancelled).to be true
  end
end
