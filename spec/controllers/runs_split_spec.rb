require "rails_helper"

RSpec.describe RunsController do
  describe "Split run" do
    render_views

    before :each do
      @user = create(:role, level: 100).user
      @provider = @user.current_provider
      @request.env["devise.mapping"] = Devise.mappings[:user]
      sign_in @user
      day = Date.current + 1
      @run = create(:run, name: "UDR5", provider: @provider, date: day,
                    scheduled_start_time: Time.zone.parse("#{day} 08:00"), scheduled_end_time: Time.zone.parse("#{day} 17:00"))
    end

    it "shows the button on the run and the split page" do
      get :show, params: { id: @run.id }
      expect(response.body).to include("Split run")
      get :split, params: { id: @run.id }
      expect(response).to be_successful
      expect(response.body).to include("UDR5 PM")
    end

    it "splits and opens the new run" do
      post :perform_split, params: { id: @run.id, at: "12:30", name: "UDR5 PM", vehicle_id: @run.vehicle_id }
      new_run = Run.find_by(name: "UDR5 PM")
      expect(response).to redirect_to(run_path(new_run))
      expect(flash[:notice]).to include("UDR5 now ends at 12:30 PM")
    end

    it "shows what was wrong" do
      post :perform_split, params: { id: @run.id, at: "18:00", name: "UDR5 PM", vehicle_id: @run.vehicle_id }
      expect(response.status).to eq 422
      expect(response.body).to include("Split between")
    end
  end
end
