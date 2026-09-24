require "rails_helper"

RSpec.describe RosterSync do
  let(:provider) { create(:provider) }

  def route(name)
    FixedRoute.create!(provider: provider, name: name, kind: "city", color: "FF0000", external_route_ids: ["fy2027-#{name.downcase}-a"])
  end

  def driver(first, last)
    user = create(:user, first_name: first, last_name: last, current_provider: provider)
    create(:driver, provider: provider, user: user)
  end

  def run_for(fixed_route, date, driver: nil)
    vehicle = build(:vehicle, provider: provider); vehicle.save!(validate: false)
    Run.create!(provider: provider, name: "#{fixed_route.name} #{date}", date: date, service_mode: "fixed_route",
                fixed_route: fixed_route, vehicle: vehicle, driver: driver,
                scheduled_start_time: Time.zone.parse("#{date} 07:30"), scheduled_end_time: Time.zone.parse("#{date} 17:00"))
  end

  let(:date)   { Date.today + 1 }
  let!(:gold)  { route("Gold") }
  let!(:green) { route("Green") }
  let!(:blue)  { route("Blue") }
  let!(:red)   { route("Red") }
  let!(:mary)  { driver("Mary", "Ramos") }
  let!(:ram)   { driver("Ramiro", "Mejia") }
  let!(:frances) { driver("Frances", "Gonzalez") }

  def roster(entries, combos = [])
    {
      "date" => date.to_s, "weekday" => date.strftime("%A"), "generated_at" => "2026-09-23T20:00:00Z",
      "categories" => { "fixed" => entries.map { |route, shift, op, status|
        { "route_shift" => "#{route} (#{shift})", "route" => route, "shift" => shift, "operator" => op, "raw" => op, "status" => status } } },
      "combos" => { "fixed" => combos.map { |op, routes| { "operator" => op, "routes" => routes } } },
    }
  end

  def sync(json, code: 200)
    described_class.new(provider: provider, url: "http://shim:8792", token: "t",
                        http: ->(_uri, headers) { expect(headers["Authorization"]).to eq "Bearer t"; [code, json.is_a?(String) ? json : json.to_json] })
  end

  it "assigns the sheet's driver, matches a shortened first name, and reports an open route" do
    run_gold = run_for(gold, date)
    run_blue = run_for(blue, date, driver: frances)
    run_red  = run_for(red, date)
    r = roster([["GOLD", "AM", "Ram Mejia", "assigned"], ["GOLD", "PM", "Ram Mejia", "assigned"],
                ["BLUE", "AM", "Frances Gonzalez", "assigned"], ["RED", "AM", "", "open"]])
    s = sync(r)
    rows = s.plan(s.fetch("tomorrow", %w[fixed]))
    by = rows.index_by(&:route)
    expect(by["GOLD"].action).to eq :assign
    expect(by["GOLD"].driver).to eq ram
    expect(by["BLUE"].action).to eq :same
    expect(by["RED"].action).to eq :open

    expect(s.apply!(rows).map(&:route)).to eq ["GOLD"]
    expect(run_gold.reload.driver).to eq ram
    expect(run_blue.reload.driver).to eq frances
    expect(run_red.reload.driver).to be_nil
    expect(PaperTrail::Version.where(item_type: "Run", item_id: run_gold.id).last.whodunnit).to eq "roster-sync"
    expect(s.alerts(rows).map(&:route)).to eq ["RED"]
  end

  it "puts a one-bus driver on the lead route and leaves the partner empty" do
    run_gold  = run_for(gold, date)
    run_green = run_for(green, date)
    r = roster([["GOLD", "AM", "Mary Ramos", "assigned"], ["GREEN", "AM", "Mary Ramos", "assigned"]],
               [["Mary Ramos", %w[GOLD GREEN]]])
    s = sync(r)
    rows = s.plan(r)
    by = rows.index_by(&:route)
    expect(by["GOLD"].action).to eq :assign
    expect(by["GREEN"].action).to eq :combo_partner
    s.apply!(rows)
    expect(run_gold.reload.driver).to eq mary
    expect(run_green.reload.driver).to be_nil
    expect(s.report(r, rows, mode: "apply")).to include("one-bus days: Mary Ramos on Gold + Green")
  end

  it "never clears a driver, never touches a started run, and flags names it cannot match" do
    run_gold = run_for(gold, date, driver: mary)
    run_gold.update_columns(actual_start_time: Time.current)
    run_blue = run_for(blue, date, driver: frances)
    r = roster([["GOLD", "AM", "Ram Mejia", "assigned"], ["BLUE", "AM", "", "open"], ["GREEN", "AM", "Nobody Known", "assigned"]])
    s = sync(r)
    rows = s.plan(r)
    by = rows.index_by(&:route)
    expect(by["GOLD"].action).to eq :started
    expect(by["BLUE"].action).to eq :keep
    expect(by["GREEN"].action).to eq :no_run
    s.apply!(rows)
    expect(run_gold.reload.driver).to eq mary
    expect(run_blue.reload.driver).to eq frances
  end

  it "skips not-in-service routes and reports unknown route names" do
    run_for(red, date)
    r = roster([["RED", "AM", "Not In Service", "not_in_service"], ["TEAL", "AM", "Mary Ramos", "assigned"]])
    s = sync(r)
    rows = s.plan(r)
    by = rows.index_by(&:route)
    expect(by["RED"].action).to eq :skip
    expect(by["TEAL"].action).to eq :unknown_route
    expect(s.alerts(rows).map(&:route)).to eq ["TEAL"]
  end

  it "on a one-bus day with a route RidePilot does not know, the run goes on the route it does" do
    run_blue = run_for(blue, date)
    r = roster([["BLUE", "AM", "Mary Ramos", "assigned"], ["AZURE/EDNA", "AM", "Mary Ramos", "assigned"]],
               [["Mary Ramos", ["AZURE/EDNA", "BLUE"]]])
    s = sync(r)
    rows = s.plan(r)
    by = rows.index_by(&:route)
    expect(by["BLUE"].action).to eq :assign
    expect(by["AZURE/EDNA"].action).to eq :unknown_route
    s.apply!(rows)
    expect(run_blue.reload.driver).to eq mary
  end

  it "reports assist (overflow) buses without matching them, and folds VIC3/EDNA onto Edna" do
    edna = FixedRoute.create!(provider: provider, name: "Edna", kind: "commuter", color: "000000", external_route_ids: ["edna-inteplast"])
    run_edna = run_for(edna, date)
    r = roster([["VIC3/EDNA", "AM", "Mary Ramos", "assigned"], ["EDNA ASSIST (AM/PM)", "AM", "Frances Gonzalez", "assigned"],
                ["BAY CITY ASSIST", "AM", "", "open"]])
    s = sync(r)
    rows = s.plan(r)
    by = rows.index_by(&:route)
    expect(by["VIC3/EDNA"].action).to eq :assign
    expect(by["VIC3/EDNA"].fixed_route).to eq edna
    expect(by["EDNA ASSIST (AM/PM)"].action).to eq :assist
    expect(by["BAY CITY ASSIST"].action).to eq :assist
    expect(s.alerts(rows)).to be_empty
    s.apply!(rows)
    expect(run_edna.reload.driver).to eq mary
    expect(s.report(r, rows, mode: "watch")).to include("overflow bus: Frances Gonzalez")
  end

  it "puts a commuter double's driver on the tandem route's run and leaves both singles empty" do
    bay = FixedRoute.create!(provider: provider, name: "Bay", kind: "commuter", color: "000000", external_route_ids: ["bay-inteplast"])
    pal = FixedRoute.create!(provider: provider, name: "Pal", kind: "commuter", color: "000000", external_route_ids: ["pal-inteplast"])
    both = FixedRoute.create!(provider: provider, name: "Bay+Pal", kind: "commuter", color: "000000", external_route_ids: ["bay-pal-inteplast"])
    run_bay = run_for(bay, date); run_pal = run_for(pal, date); run_both = run_for(both, date)
    cindy = driver("Cindy", "Perales")
    r = roster([["BAY", "AM", "Cindy Perales", "assigned"], ["PAL", "AM", "Cindy Perales", "assigned"]],
               [["Cindy Perales", %w[BAY PAL]]])
    s = sync(r)
    rows = s.plan(r)
    by = rows.index_by(&:route)
    expect(by["BAY"].action).to eq :combo_partner
    expect(by["PAL"].action).to eq :combo_partner
    expect(by["BAY+PAL"].action).to eq :assign
    expect(s.alerts(rows)).to be_empty
    s.apply!(rows)
    expect(run_both.reload.driver).to eq cindy
    expect(run_bay.reload.driver).to be_nil
    expect(run_pal.reload.driver).to be_nil

    # No run for the tandem that day: an alert, and the singles still stay empty.
    run_both.destroy
    rows = s.plan(r)
    expect(rows.index_by(&:route)["BAY+PAL"].action).to eq :no_run
    expect(s.alerts(rows).map(&:route)).to eq ["BAY+PAL"]
  end

  it "turns the shim's errors into one line" do
    expect { sync({ "error" => "PayPeriodNotCreated" }).fetch("2027-01-01", %w[fixed]) }.to raise_error(RosterSync::Error, /PayPeriodNotCreated/)
    expect { sync("nope", code: 401).fetch("tomorrow", %w[fixed]) }.to raise_error(RosterSync::Error, /HTTP 401/)
  end
end
