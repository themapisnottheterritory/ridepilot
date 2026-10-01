require "rails_helper"

# Tasha, 2026-10-01: match each driver's cash to the fares the tablet recorded.
RSpec.describe ReportsController do
  describe "fares_collected" do
    render_views

    before :each do
      @user = create(:role, level: 100).user
      @provider = @user.current_provider
      @request.env["devise.mapping"] = Devise.mappings[:user]
      sign_in @user
      @report = create(:custom_report, name: 'fares_collected', version: '2', redirect_to_results: true)
      now = Time.zone.now.change(hour: 10)
      @run = create(:run, provider: @provider)
      @cash = create(:trip, provider: @provider, run: @run, fare_amount: 2.0, fare_collected_time: now)
      @card = create(:trip, provider: @provider, run: @run, fare_amount: 1.5, fare_collected_time: now + 1.hour)
      FareTransaction.create!(provider: @provider, customer: @card.customer, trip: @card, kind: 'debit', amount: -1.5,
                              balance_after: 0, recorded_at: now + 1.hour, client_uuid: SecureRandom.uuid)
      create(:trip, provider: @provider, run: @run, fare_amount: 2.0, fare_collected_time: nil)            # not collected
      create(:trip, provider: create(:provider), fare_amount: 9.0, fare_collected_time: now)               # another agency
    end

    let(:params) { { id: @report.id, query: { start_date: Date.current.to_s, before_end_date: Date.current.to_s, group_by: "driver" } } }

    it "lists each fare and totals them by driver, cash apart from card" do
      get :fares_collected, params: params
      expect(response).to be_successful
      expect(assigns(:fares).map { |f| [f[:trip].id, f[:paid_by]] }).to eq [[@cash.id, "Cash"], [@card.id, "Card"]]
      g = assigns(:grand)
      expect([g[:count], g[:cash], g[:card], g[:total]]).to eq [2, 2.0, 1.5, 3.5]
      expect(assigns(:report_data).map { |r| r[:label] }).to eq [@run.driver.user_name]
      expect(response.body).to include("Each fare")
    end

    it "downloads a row per fare as CSV" do
      get :fares_collected, params: params.deep_merge(query: { report_format: "csv" })
      expect(response).to be_successful
      lines = response.body.lines.map(&:strip).reject(&:blank?)
      expect(lines).to include(a_string_starting_with("Collected,Run,Driver"))
      expect(lines.count { |l| l.end_with?(",#{@cash.id}") || l.end_with?(",#{@card.id}") }).to eq 2
    end
  end
end
