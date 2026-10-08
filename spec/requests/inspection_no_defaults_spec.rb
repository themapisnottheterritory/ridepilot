require "rails_helper"

# 2026-10-08, Kristie: pre/post-trip items start unanswered on the 1.0.34 app,
# and the server refuses a report from it with anything left unchecked.
RSpec.describe "Inspection reports need every item answered", type: :request do
  let(:run)    { create(:run, date: Date.current).tap { |r| r.driver.update_column(:provider_id, r.provider_id) } }
  let(:driver) { run.driver }
  let(:items)  { create_list(:vehicle_inspection, 3, provider: run.provider) }
  def headers(code)
    driver.user.ensure_authentication_token; driver.user.save!
    h = { "X-User-Username" => driver.user.username, "X-User-Token" => driver.user.authentication_token }
    code ? h.merge("X-App-Version" => "1.0.#{code - 1}", "X-App-Code" => code.to_s) : h
  end

  def post_report(code:, statuses:, safe: true)
    body = { inspection_report: { run_id: run.id, phase: "pre", odometer: 1000, safe_to_operate: safe, certified_at: Time.current.iso8601 },
             items: items.zip(statuses).map { |it, st| { vehicle_inspection_id: it.id, status: st, defect_note: "" } } }
    post "/api/v1/inspection_reports", params: body.to_json, headers: headers(code).merge("Content-Type" => "application/json")
    response
  end

  it "takes a fully answered report from 1.0.34" do
    expect(post_report(code: 35, statuses: %w[ok na ok]).status).to eq 200
    expect(VehicleInspectionReport.where(run_id: run.id).count).to eq 1
  end

  it "refuses an unchecked item from 1.0.34 and saves nothing" do
    r = post_report(code: 35, statuses: ["ok", "", nil])
    expect(r.status).to eq 422
    expect(r.body).to include("2 items not checked")
    expect(VehicleInspectionReport.where(run_id: run.id).count).to eq 0
  end

  it "refuses a 1.0.34 report with neither Safe nor NOT safe" do
    r = post_report(code: 35, statuses: %w[ok ok ok], safe: nil)
    expect(r.status).to eq 422
    expect(r.body).to include("Pick Safe or NOT safe")
  end

  it "keeps taking older apps, where a blank still means OK" do
    expect(post_report(code: 34, statuses: ["ok", "", "defect"]).status).to eq 200
    expect(post_report(code: nil, statuses: ["", "", ""]).status).to eq 200
  end
end
