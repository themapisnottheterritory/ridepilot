require "rails_helper"

# Each tablet's own number (MTN) on the Tablets page (Ron, 2026-10-11).
RSpec.describe "Tablet phone numbers", type: :request do
  include Devise::Test::IntegrationHelpers
  def report(phone: nil, name: nil)
    net = { "carrier" => "Verizon" }
    net["phoneNumber"] = phone if phone
    post "/api/v1/tablet_report", params: { report: { device: { androidId: "abc123", model: "SM-T547U" }, network: net },
                                            app: { name: name, version: "1.0.41" }.compact }, as: :json
    expect(response.status).to eq 200
    Tablet.find_by!(android_id: "abc123")
  end

  it "keeps the SIM's number as ten digits, through reports that don't carry it" do
    expect(report(phone: "+13615551234").phone_number).to eq "3615551234"
    expect(report(name: "fixed").phone_number).to eq "3615551234"   # Fixed Route doesn't send it
    t = report(phone: "3615559876")                                 # SIM swapped
    expect(t.phone_label).to eq "(361) 555-9876"
    expect(t.phone_source).to eq "from the SIM"
  end

  it "ignores what isn't a phone number" do
    expect(report(phone: "Unknown").phone_number).to be_nil
  end

  describe "typed on the Tablets page" do
    let(:admin) { create(:super_admin) }
    let(:tablet) { report }
    before { sign_in admin }

    it "saves a typed number in any format, and clears it" do
      patch "/en/tablets/#{tablet.id}", params: { tablet: { phone_typed: "361.555.0123", notes: "bus 1705" } }
      tablet.reload
      expect([tablet.phone_typed, tablet.notes, tablet.phone_label, tablet.phone_source]).to eq ["3615550123", "bus 1705", "(361) 555-0123", "typed"]
      patch "/en/tablets/#{tablet.id}", params: { tablet: { phone_typed: "" } }
      expect(tablet.reload.phone_typed).to be_nil
      expect(tablet.notes).to eq "bus 1705"
    end

    it "refuses a number that isn't ten digits and saves nothing" do
      patch "/en/tablets/#{tablet.id}", params: { tablet: { phone_typed: "555-0123", notes: "x" } }
      expect(flash[:alert]).to include "isn't a 10-digit phone number"
      expect(tablet.reload.notes).to be_nil
    end

    it "flags a typed number the SIM disagrees with, and shows both pages" do
      tablet.update!(phone_typed: "3615550000")
      report(phone: "13615551234")
      expect(tablet.reload.issues).to include [:warn, "Phone typed as (361) 555-0000, but the SIM says (361) 555-1234"]
      get "/en/tablets"
      expect(response.body).to include "(361) 555-1234"
      get "/en/tablets/#{tablet.id}"
      expect(response.body).to include("Phone (MTN)").and include("from the SIM")
    end
  end
end
