require "rails_helper"

RSpec.describe FareAccountsController, type: :controller do
  render_views
  login_admin_as_current_user

  let(:provider) { @current_user.current_provider }
  let(:rider)    { create_rider(provider) }

  describe "GET #index" do
    it "lists riders with a token or a balance and today's takings" do
      FareLedger.new(rider, provider: provider).load!(10, payment_method: "cash")
      nobody = create_rider(provider)
      get :index
      expect(response).to have_http_status(:ok)
      expect(assigns(:accounts)).to include(rider)
      expect(assigns(:accounts)).not_to include(nobody)
      expect(assigns(:today_loads)).to eq("cash" => 10)
      expect(response.body).to include("Fare Cards")
    end
  end

  describe "GET #lookup" do
    it "sends a tapped card to its rider's account" do
      t = FareToken.create!(provider: provider, customer: rider, kind: "rfid", uid: "04A3B2C1")
      get :lookup, params: { q: "04 a3 b2 c1" }
      expect(response).to redirect_to(customer_fare_account_path(rider, token_id: t.id))
    end

    it "finds a card by its printed serial" do
      t = FareToken.create!(provider: provider, customer: rider, kind: "rfid", uid: "04A3B2C1", serial: "55")
      get :lookup, params: { q: "#55" }
      expect(response).to redirect_to(customer_fare_account_path(rider, token_id: t.id))
    end

    it "offers to issue an unknown card" do
      get :lookup, params: { q: "DEADBEEF01" }
      expect(response).to redirect_to(fare_accounts_path(unknown_uid: "DEADBEEF01"))
      expect(flash[:alert]).to match(/No card/)
    end
  end

  describe "GET #show" do
    it "renders the account with its tokens and ledger" do
      FareToken.create!(provider: provider, customer: rider, kind: "rfid", uid: "04A3B2C1")
      FareLedger.new(rider, provider: provider, by: @current_user).load!(20, payment_method: "check", reference: "778")
      get :show, params: { id: rider.id }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("04 A3 B2 C1")
      expect(response.body).to include("$20.00")
      expect(response.body).to include("#778")
    end
  end
end

RSpec.describe FareTransactionsController, type: :controller do
  login_admin_as_current_user
  let(:provider) { @current_user.current_provider }
  let(:rider)    { create_rider(provider) }

  it "posts a cash load from the desk form" do
    post :create, params: { customer_id: rider.id, fare_transaction: { kind: "load", amount: "$10.00", payment_method: "cash" } }
    expect(response).to redirect_to(customer_fare_account_path(rider, tx_id: FareTransaction.last.id))
    expect(rider.reload.fare_balance).to eq 10
    expect(FareTransaction.last.recorded_by).to eq @current_user
  end

  it "goes to the receipt when asked" do
    post :create, params: { customer_id: rider.id, fare_transaction: { kind: "load", amount: "10", payment_method: "check", reference: "12", receipt: "1" } }
    expect(response).to redirect_to(fare_transaction_path(FareTransaction.last))
  end

  it "refuses an adjustment without a reason" do
    post :create, params: { customer_id: rider.id, fare_transaction: { kind: "adjust", amount: "-3" } }
    expect(flash[:alert]).to match(/Note/)
    expect(rider.reload.fare_balance).to eq 0
  end
end

RSpec.describe FareTokensController, type: :controller do
  login_admin_as_current_user
  let(:provider) { @current_user.current_provider }
  let(:rider)    { create_rider(provider) }

  it "issues a card and records who did it" do
    post :create, params: { customer_id: rider.id, fare_token: { kind: "rfid", uid: "04 a3 b2 c1", serial: "9" } }
    t = FareToken.last
    expect(t.uid).to eq "04A3B2C1"
    expect(t.customer).to eq rider
    expect(t.provider).to eq provider
    expect(t.issued_by).to eq @current_user
    expect(response).to redirect_to(customer_fare_account_path(rider, token_id: t.id))
  end

  it "marks a card lost" do
    t = FareToken.create!(provider: provider, customer: rider, kind: "rfid", uid: "04A3B2C1")
    patch :update, params: { id: t.id, status: "lost" }
    expect(t.reload.status).to eq "lost"
  end
end

RSpec.describe FareTransactionsController, "pass buttons", type: :controller do
  login_admin_as_current_user
  let(:provider) { @current_user.current_provider }
  let(:senior)   { RiderCategory.find_or_create_by!(name: "Senior 60+") { |c| c.default_fare = 0.50 } }
  let(:rider)    { create_rider(provider, default_rider_category_id: senior.id) }

  it "sells a 10-ride pass from the rider's category, at that pass's own discount" do
    provider.update!(fare_pass_10_discount_pct: 10, fare_pass_20_discount_pct: 20)
    post :create, params: { customer_id: rider.id, fare_transaction: { kind: "pass_10", payment_method: "cash" } }
    expect(response).to redirect_to(customer_fare_account_path(rider, tx_id: FareTransaction.last.id))
    expect(rider.reload.fare_balance).to eq 5.0
    expect(FareTransaction.last.tendered).to eq 4.5
    expect(flash[:notice]).to include("10-ride pass")
    post :create, params: { customer_id: rider.id, fare_transaction: { kind: "pass_20", payment_method: "cash" } }
    expect(rider.reload.fare_balance).to eq 15.0
    expect(FareTransaction.last.tendered).to eq 8.0
  end

  it "sells a monthly pass for next month at the provider price and prints a receipt" do
    provider.update!(fare_monthly_pass_price: 30)
    post :create, params: { customer_id: rider.id, fare_transaction: { kind: "pass_monthly", pass_month: "next", payment_method: "check", reference: "44", receipt: "1" } }
    expect(response).to redirect_to(fare_transaction_path(FareTransaction.last))
    expect(rider.reload.fare_pass_expires_on).to eq Date.current.next_month.end_of_month
    expect(rider.fare_balance).to eq 0
  end

  it "refuses a monthly pass with no price set" do
    post :create, params: { customer_id: rider.id, fare_transaction: { kind: "pass_monthly", pass_month: "this", payment_method: "cash" } }
    expect(flash[:alert]).to match(/No monthly pass price/)
  end
end

RSpec.describe FareTransactionsController, "reduced-fare monthly", type: :controller do
  login_admin_as_current_user
  let(:provider) { @current_user.current_provider }
  let!(:adult)   { RiderCategory.find_or_create_by!(name: "Adult") { |c| c.default_fare = 1.00 } }
  let(:senior)   { RiderCategory.find_or_create_by!(name: "Senior 60+") { |c| c.default_fare = 0.50 } }
  let(:youth)    { RiderCategory.find_or_create_by!(name: "Youth 5-17") { |c| c.default_fare = 0.75 } }

  before { provider.update!(fare_monthly_pass_price: 30, fare_monthly_pass_price_reduced: 15) }

  it "charges $15 to a senior and a youth, $30 to an adult" do
    expect(provider.monthly_pass_price_for(senior)).to eq 15
    expect(provider.monthly_pass_price_for(youth)).to eq 15
    expect(provider.monthly_pass_price_for(adult)).to eq 30
    expect(provider.monthly_pass_price_for(nil)).to eq 30
    rider = create_rider(provider, default_rider_category_id: senior.id)
    post :create, params: { customer_id: rider.id, fare_transaction: { kind: "pass_monthly", pass_month: "this", payment_method: "cash" } }
    expect(FareTransaction.last.amount).to eq(-15)
    expect(rider.reload.fare_pass_expires_on).to eq Date.current.end_of_month
  end

  it "uses the full price for everyone when no reduced price is set" do
    provider.update!(fare_monthly_pass_price_reduced: 0)
    expect(provider.monthly_pass_price_for(senior)).to eq 30
  end
end
