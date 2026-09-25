require 'rails_helper'

RSpec.describe Api::V2::BaseController, type: :controller do 
  # This line is necessary to get Devise scoped tests to work.
  before(:each) { @request.env["devise.mapping"] = Devise.mappings[:user] }

  let(:user) { create(:user) }
  
  let(:headers_reg_valid) { {"X-USER-USERNAME" => user.username, "X-USER-TOKEN" => user.authentication_token} }
  let(:headers_reg_invalid) { {"X-USER-USERNAME" => user.username, "X-USER-TOKEN" => "FAKEAUTHTOKEN"} }
  let(:headers_reg_incomplete) { {"X-USER-USERNAME" => user.username } }

  context 'user authentication' do
    
    it 'authenticates registered user if valid auth headers are passed' do
      request.headers.merge!(headers_reg_valid)
      get :touch_session, format: :json
      expect(response).to be_successful
    end
    
    it 'throws 401 error if invalid auth headers are passed' do
      request.headers.merge!(headers_reg_invalid)
      get :touch_session, format: :json
      expect(response).to have_http_status(:unauthorized)
    end
    
    it 'throws 401 error if username only is passed' do
      request.headers.merge!(headers_reg_incomplete)
      get :touch_session, format: :json
      expect(response).to have_http_status(:unauthorized)
    end
    
    it 'throws 401 error if no auth headers are passed' do
      get :touch_session, format: :json
      expect(response).to have_http_status(:unauthorized)
    end
      
  end

end