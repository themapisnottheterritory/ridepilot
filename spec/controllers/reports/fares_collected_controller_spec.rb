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

    it "groups every agency the user has a role in, and only those" do
      goliad = create(:provider, name: "Goliad")
      create(:role, user: @user, provider: goliad, level: 0)
      theirs = create(:trip, provider: goliad, fare_amount: 3.0, fare_collected_time: Time.zone.now.change(hour: 9))
      hidden = create(:provider, name: "Lavaca")
      create(:trip, provider: hidden, fare_amount: 4.0, fare_collected_time: Time.zone.now.change(hour: 9))
      get :fares_collected, params: params.deep_merge(query: { agencies: "all" })
      sections = assigns(:agency_sections)
      expect(sections.map { |a| a[:agency] }).to eq [@provider.name, "Goliad"].sort_by { |n| [@provider, goliad].find { |p| p.name == n }.id }
      expect(sections.map { |a| a[:total][:total] }).to match_array [3.5, 3.0]
      expect(assigns(:fares).map { |f| f[:trip].id }).to include(theirs.id)
      expect(assigns(:grand)[:total]).to eq 6.5
      expect(response.body).to include("Goliad total", "All agencies")
    end

    it "stays on the current agency unless all are asked for" do
      create(:role, user: @user, provider: create(:provider), level: 0)
      get :fares_collected, params: params
      expect(assigns(:agency_sections).size).to eq 1
      expect(assigns(:grand)[:total]).to eq 3.5
    end

    it "downloads the same rows as an Excel workbook, amounts as numbers" do
      get :fares_collected, params: params.deep_merge(query: { report_format: "xlsx" })
      expect(response).to be_successful
      sheet = RubyXL::Parser.parse_buffer(response.body)[0]
      expect(sheet.sheet_name).to eq @report.title.first(31)
      rows = sheet.sheet_data.rows.compact.map { |r| r.cells.map { |c| c&.value } }
      header = rows.index { |r| r.first == "Agency" && r[1] == "Collected" }
      expect(header).to be_present
      amounts = rows[(header + 1)..].map { |r| r[7] }
      expect(amounts).to contain_exactly(2, 1.5)
      expect(amounts).to all(be_a(Numeric))
    end

    it "downloads a row per fare as CSV" do
      get :fares_collected, params: params.deep_merge(query: { report_format: "csv" })
      expect(response).to be_successful
      lines = response.body.lines.map(&:strip).reject(&:blank?)
      expect(lines).to include(a_string_starting_with("Agency,Collected,Run,Driver"))
      expect(lines.count { |l| l.end_with?(",#{@cash.id}") || l.end_with?(",#{@card.id}") }).to eq 2
    end
  end
end
