require 'rails_helper'

RSpec.describe Api::V2::SessionsController, type: :controller do 
  let(:user) { create :user }

  describe "user sign in/sign out" do
    
    it 'signs in an existing user' do
      pw = attributes_for(:user)[:password]
      post :create, format: :json, params: { user: { username: user.username, password: pw } }
      
      expect(response).to be_successful
      
      parsed_response = JSON.parse(response.body)
      
      # Expect a session hash with an username and auth token
      expect(parsed_response["data"]["session"]["username"]).to eq(user.username)
      expect(parsed_response["data"]["session"]["authentication_token"]).to eq(user.authentication_token)  
    end
    
    it 'requires password for sign in' do
      pw = "somerandombadpw"
      post :create, format: :json, params: { user: { username: user.username, password: pw } }
      
      expect(response).to have_http_status(:unauthorized)
    end
    
    it 'signs out a user' do
      original_auth_token = user.authentication_token
      
      request.headers['X-USER-TOKEN'] = original_auth_token
      request.headers['X-USER-USERNAME'] = user.username
      delete :destroy, format: :json
      
      expect(response).to be_successful
      
      # Expect user to have a new auth token after sign out
      user.reload
      expect(user.authentication_token).not_to eq(original_auth_token)
    end

    it 'requires a valid auth token for sign out' do
      original_auth_token = user.authentication_token
      
      request.headers['X-User-Token'] = original_auth_token + "_bloop"
      request.headers['X-User-Email'] = user.username
      delete :destroy, format: :json
      
      expect(response).to have_http_status(:unauthorized)
      
      # Expect user to have the same auth token
      user.reload
      expect(user.authentication_token).to eq(original_auth_token)
    end
    
  end
end