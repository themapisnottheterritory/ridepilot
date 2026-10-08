require "rails_helper"

# 2026-10-08: any table on screen can be downloaded as PDF, CSV or Excel.
RSpec.describe "Table downloads", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:staff) { create(:role, level: Role::ADMIN_LEVEL).user }
  let(:table) do
    { title: "Trips: Oct 9", subtitle: "UDR", columns: ["Rider", "Phone", "Miles", "Fare", "Zip"],
      rows: [["Mary Ramos", "(361) 555-1000", "12.5", "$2.00", "07901"], ["Joe Garza", "", "1,204", "$1,250.75", "77901"]] }.to_json
  end
  before { sign_in staff }

  def export(fmt)
    post "/table_exports", params: { export_format: fmt, table: table }
    response
  end

  it "needs a signed-in user" do
    sign_out staff
    expect(export("csv").status).to eq(302).or eq(401)
  end

  it "CSV, readable by Excel" do
    r = export("csv")
    expect(r.headers["Content-Disposition"]).to include("trips-oct-9-")
    body = r.body.force_encoding("UTF-8")
    expect(body).to start_with("﻿Rider,Phone,Miles,Fare,Zip")
    expect(body).to include("Mary Ramos,(361) 555-1000,12.5,$2.00,07901")
  end

  it "Excel, with numbers as numbers and zip codes kept as text" do
    r = export("xlsx")
    expect(r.media_type).to eq "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    sheet = nil
    Zip::File.open_buffer(StringIO.new(r.body)) { |z| sheet = z.read("xl/worksheets/sheet1.xml") }
    expect(sheet).to include("<v>12.5</v>").and include("<v>1204</v>").and include("<v>1250.75</v>")
    expect(sheet).to include("07901")
    expect(sheet).to include("pane")
  end

  it "PDF in the house style" do
    r = export("pdf")
    expect(r.media_type).to eq "application/pdf"
    expect(r.body[0, 4]).to eq "%PDF"
  end

  it "refuses an unknown format or junk" do
    expect(export("exe").status).to eq 422
    post "/table_exports", params: { export_format: "csv", table: "nope" }
    expect(response.status).to eq 422
  end
end
