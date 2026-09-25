require "rails_helper"

RSpec.describe "Users" do
  describe "GET /users/sign_in" do
    attr_reader :user
    
    before do
      @user = create(:admin)
    end
    
    it "signs me in" do
      visit new_user_session_path
      fill_in 'user_username', with: @user.username
      fill_in 'user_password', :with => 'password'
      click_button 'Log In'
      
      # TODO add sme actual assertions
    end
  end
end
