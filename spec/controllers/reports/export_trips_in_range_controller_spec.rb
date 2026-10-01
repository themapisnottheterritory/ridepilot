require "rails_helper"

RSpec.describe ReportsController do
  describe "export_trips_in_range" do
    before :each do
      @user = create(:role, level: 100).user
      @provider = @user.current_provider
      @request.env["devise.mapping"] = Devise.mappings[:user]
      sign_in @user
    end

    it "downloads this agency's trips in the range as CSV, and no other agency's" do
      mine = create(:trip, provider: @provider, pickup_time: Time.current.change(hour: 9))
      theirs = create(:trip, provider: create(:provider), pickup_time: Time.current.change(hour: 9))
      get :export_trips_in_range, params: { id: create(:custom_report, name: "export_trips_in_range").id, query: { start_date: Date.current.to_s, before_end_date: Date.current.to_s } }
      expect(response).to be_successful
      expect(response.media_type).to eq "text/csv"
      rows = CSV.parse(response.body, headers: true)
      expect(rows.map { |r| r["trips.id"].to_i }).to eq [mine.id]
      expect(rows.map { |r| r["trips.id"].to_i }).not_to include theirs.id
    end
  end
end
