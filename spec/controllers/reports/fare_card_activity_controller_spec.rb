require "rails_helper"

RSpec.describe ReportsController do
  describe "fare_card_activity" do
    render_views

    before :each do
      @user = create(:role, level: 100).user
      @provider = @user.current_provider
      @request.env["devise.mapping"] = Devise.mappings[:user]
      sign_in @user
      @report = create(:custom_report, name: 'fare_card_activity', version: '2', redirect_to_results: true)
      @rider = create_rider(@provider)
      ledger = FareLedger.new(@rider, provider: @provider, by: @user)
      ledger.load!(20, payment_method: "cash")
      ledger.load!(5, payment_method: "check", reference: "41")
      ledger.debit!(1.5)
      ledger.debit!(1.5)
      ledger.refund!(2, note: "overcharged")
    end

    it "sums the desk takings, fares, refunds and what riders still hold" do
      get :fare_card_activity, params: { id: @report.id,
        query: { start_date: Date.current.to_s, before_end_date: Date.current.to_s, group_by: "day" } }
      expect(response).to be_successful
      g = assigns(:grand)
      expect(g[:cash]).to eq 20.0
      expect(g[:check]).to eq 5.0
      expect(g[:fares]).to eq 3.0
      expect(g[:refunds]).to eq 2.0
      expect(g[:net]).to eq 24.0
      expect(g[:outstanding]).to eq 24.0
      expect(assigns(:report_data).size).to eq 1
      expect(response.body).to include("Riders hold on account today")
    end

    it "groups by payment method" do
      get :fare_card_activity, params: { id: @report.id,
        query: { start_date: Date.current.to_s, before_end_date: Date.current.to_s, group_by: "payment_method" } }
      labels = assigns(:report_data).map { |g| g[:label] }
      expect(labels).to include("Cash", "Check", "Fare", "Refund")
    end

    it "exports csv" do
      get :fare_card_activity, params: { id: @report.id,
        query: { start_date: Date.current.to_s, before_end_date: Date.current.to_s, report_format: "csv" } }
      expect(response).to be_successful
      expect(response.body).to include("Cash in")
    end
  end
end

RSpec.describe FareTransactionsController, type: :controller do
  render_views
  login_admin_as_current_user

  it "renders a receipt" do
    rider = create_rider(@current_user.current_provider)
    tx = FareLedger.new(rider, provider: rider.provider, by: @current_user).load!(10, payment_method: "cash")
    get :show, params: { id: tx.id }
    expect(response).to be_successful
    expect(response.body).to include("Fare card receipt")
    expect(response.body).to include("$10.00")
  end
end
