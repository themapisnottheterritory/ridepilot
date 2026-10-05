require "rails_helper"

# Michelle, 2026-10-05: she filtered the Trips list by a customer, then deleted
# that (duplicate) customer; the remembered filter made every load of the Trips
# page crash ("undefined method `name' for nil").
RSpec.describe TripsController, type: :controller do
  login_admin_as_current_user
  render_views

  it "forgets a remembered customer who has since been deleted, and the page loads" do
    customer = create(:customer, provider: @current_user.current_provider)
    session[:trips_customer_id] = customer.id.to_s
    customer.destroy
    get :index
    expect(response).to have_http_status(:ok)
    expect(session[:trips_customer_id]).to be_nil
  end

  it "keeps a remembered customer who still exists" do
    customer = create(:customer, provider: @current_user.current_provider)
    session[:trips_customer_id] = customer.id.to_s
    get :index
    expect(response).to have_http_status(:ok)
    expect(session[:trips_customer_id]).to eq customer.id.to_s
  end
end
