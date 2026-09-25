require 'rails_helper'

RSpec.describe Api::V2::PasswordsController, type: :controller do 
  let(:user) { create :user }

  describe "reset password" do
    
    it 'requires username' do
      post :reset, format: :json, params: {}
      
      expect(response).to have_http_status(:bad_request)
    end
    
    it 'requires valid username' do
      username = "somerandombadpw"
      post :reset, format: :json, params: { user: { username: username } }
      
      expect(response).to have_http_status(:bad_request)
    end
    
    it 'sends password reset instructions to valid user email' do
      post :reset, format: :json, params: { user: { username: user.username } }
      
      expect(response).to be_successful
    end
    
  end
end