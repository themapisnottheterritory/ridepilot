require "rails_helper"

RSpec.describe Api::V1::CustomersController, type: :controller do

  context "authenticate customer" do

    it "returns 403 when not passing user token in request header" do
      get :show
      expect(response.status).to be(403)
    end

    it "returns 401 when not passing invalid user token in request header" do
      request.headers.merge!({"X-RIDEPILOT-TOKEN" => SecureRandom.uuid})
      get :show
      expect(response.status).to be(401)
    end   

    it "returns 200 when passing valid user token and customer params" do 
      customer = create(:customer)
      booking_user = create(:booking_user, url: "http://localhost:3000")
      request.headers.merge!({"X-RIDEPILOT-TOKEN" => booking_user.token})
      get :show, params: {
        customer_id: customer.id, 
        customer_token: customer.token,
        provider_id: customer.provider_id
        }
      
      expect(response.body).to match("{}")
      expect(response.status).to be(200)
    end

  end

end