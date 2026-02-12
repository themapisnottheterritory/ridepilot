require "rails_helper"

RSpec.describe "DriverCompliances" do
  context "for admin" do
    before :each do
      @admin = create(:admin)
      visit new_user_session_path
      fill_in 'user_username', :with => @admin.username
      fill_in 'Password', :with => @admin.password
      click_button 'Log In'
      
      @driver = create :driver, :provider => @admin.current_provider
      @incomplete_driver_compliance = create :driver_compliance, driver: @driver
      @past_driver_compliance = create :driver_compliance, driver: @driver, compliance_date: Date.current
    end

    # Document Associations have been refactored    
    # it_behaves_like "it accepts nested attributes for document associations" do
    #   before do
    #     @owner = @driver
    #     @example = @past_driver_compliance
    #   end
    # end

    describe "GET /drivers/:id" do
      before do
        visit driver_path(id: @driver.to_param)
      end
      
      it "does not completed compliance event by default" do
        expect(page).not_to have_text @past_driver_compliance.event
      end

      it "shows the name of the compliance event" do
        expect(page).to have_text @incomplete_driver_compliance.event
      end
      
      it "shows the due date of the compliance event" do
        expect(page).to have_text @incomplete_driver_compliance.due_date.to_fs(:long)
      end
    end

    describe "GET /drivers/:id/edit" do
      before do
        visit edit_driver_path(id: @driver.to_param)
      end
      
      # TODO Pending acceptance and merge of capybara_js branch into develop
      skip "shows a link to delete the compliance event", js: true do
      end
      
      # TODO Pending acceptance and merge of capybara_js branch into develop
      skip "shows a link to edit the compliance event", js: true do
      end
      
      # TODO Pending acceptance and merge of capybara_js branch into develop
      skip "shows a link to add a new compliance event", js: true do
      end
    end
  end
end
