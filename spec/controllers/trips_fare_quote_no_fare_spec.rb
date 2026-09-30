require "rails_helper"

# The trip form's fare quote follows the funding source picked on the form.
RSpec.describe TripsController, "fare quote with a no-fare funding source", type: :controller do
  login_admin_as_current_user
  render_views

  it "follows the funding source chosen on the form" do
    paid = FundingSource.create!(name: "Title III - New Horizons", no_fare: true, fare_note: "billed to New Horizons monthly")
    get :fare_quote, params: { funding_source_id: paid.id }
    expect(response.body).to include("No fare", "billed to New Horizons monthly", "Don't collect a fare")
  end
end
