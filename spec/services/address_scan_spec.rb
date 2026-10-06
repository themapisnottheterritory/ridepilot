require "rails_helper"
require "rake"

RSpec.describe AddressScan do
  let(:provider) { create(:provider) }
  let(:group) { create(:address_group) }
  def place(name, lat, lon, city: "Victoria", address: "100 Main St")
    ProviderCommonAddress.create!(provider: provider, address_group: group, name: name, address: address, city: city, state: "TX", zip: "77901",
                                  the_geom: lat && Address.compute_geom(lat, lon))
  end
  def kinds = AddressScan.new.findings.group_by(&:kind).transform_values { |fs| fs.map(&:label) }

  it "finds a pin outside the service area and a place with no pin" do
    ok = place("Fine", 28.80, -97.00)
    ok.update_column(:the_geom, Address.compute_geom(28.80, -97.00))
    away = place("Abroad", 28.80, -97.00, address: "1 Far Rd")
    away.update_column(:the_geom, RGeo::Geographic.spherical_factory(srid: 4326).point(-84.0, 29.48))
    place("Unpinned", nil, nil, address: "2 Blank St")
    k = kinds
    expect(k["out_of_area"].join).to include("Abroad")
    expect(k["no_pin"].join).to include("Unpinned")
    expect(k.values.flatten.join).not_to include("Fine")
  end

  it "finds a place pinned far from the rest of its town" do
    6.times { |i| place("V#{i}", 28.80 + i * 0.001, -97.00, address: "#{i} Elm St") }
    place("Wrong town", 30.20, -97.00, address: "9 Oak St")
    expect(kinds["far_from_town"].join).to include("Wrong town")
  end

  it "finds an upcoming trip over 100 miles, and a saved place entered twice under the same name" do
    trip = create(:trip, provider: provider, pickup_time: 2.days.from_now)
    trip.update_column(:drive_distance, 313.2)
    place("Clinic", 28.8, -97.0, address: "5 Pine St"); place("Clinic", 28.8, -97.0, address: "5 Pine St")
    place("WIC", 28.8, -97.0, address: "5 Pine St")    # another service at the same address is not a duplicate
    k = kinds
    expect(k["trip_far"].join).to include("Trip #{trip.id}")
    expect(k["duplicate"].size).to eq 1
  end

  describe "trip addresses pinned far from home" do
    # Victoria is a town we serve: 30 or more of our addresses (TownCentres)
    before do
      30.times { |i| place("V#{i}", 28.80 + i * 0.0005, -97.00, address: "#{i} Elm St") }
      TownCentres.instance_variable_set(:@all, nil)
    end
    after { TownCentres.instance_variable_set(:@all, nil) }
    def trip_to(lat, lon, city: "Victoria", address: "1 Typed Rd", when_: 1.day.from_now)
      a = create(:address, address: "1 Typed Rd", city: "Victoria", state: "TX", the_geom: nil)
      a.update_columns(address: address, city: city, the_geom: RGeo::Geographic.spherical_factory(srid: 4326).point(lon, lat))
      create(:trip, provider: provider, pickup_time: when_, dropoff_address: a)
    end
    def far = AddressScan.new.findings.select { |f| f.kind == "trip_pin_far" }

    it "flags a pin outside Texas (a longitude missing its minus sign), with the trip to fix" do
      t = trip_to(28.80, 97.00, city: "", address: "")
      f = far.find { |x| x.record_id == t.id }
      expect(f.detail).to match(/outside Texas, [\d,]+ miles from Victoria/)
      expect(f.label).to include("coordinates 28.8, 97.0")
      expect(AddressScan.fix_path(f)).to eq "/en/trips/#{t.id}/edit"
    end

    it "flags a pin far from its own town, or with no town of ours far from every town we serve" do
      wrong = trip_to(29.40, -97.00)                                  # Victoria, 40 miles north
      lost  = trip_to(31.50, -97.00, city: "Nowhere")                 # no such town of ours, ~185 miles
      fine  = trip_to(28.81, -97.01)
      near  = trip_to(29.20, -97.00, city: "Elsewhere")                 # ~28 miles: a trip out of town, fine
      old   = trip_to(31.50, -97.00, city: "Yonder", when_: 10.days.ago)
      ids = far.map(&:record_id)
      expect(ids).to include(wrong.id, lost.id)
      expect(ids).not_to include(fine.id, near.id, old.id)
      expect(far.find { |f| f.record_id == wrong.id }.detail).to match(/\A\d+ miles from the middle of Victoria\z/)
      expect(far.find { |f| f.record_id == lost.id }.detail).to include("nearest town we serve")
    end

    it "gives the map each pin, the nearest town we serve and how far" do
      t = trip_to(28.80, 97.00, city: "", address: "")
      pin = AddressScan.pins(AddressScan.new.findings).find { |p| p[:kind] == "trip_pin_far" }
      expect(pin).to include(lat: 28.8, lon: 97.0, town: "Victoria", fix: "/en/trips/#{t.id}/edit")
      expect(pin[:miles]).to be > 8000
      (sw_lat, sw_lon), (ne_lat, ne_lon) = AddressScan.served_bounds
      expect(28.80).to be_between(sw_lat, ne_lat)
      expect(-97.00).to be_between(sw_lon, ne_lon)
    end
  end

  describe "rake addresses:scan" do
    before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?("addresses:scan") }
    let(:state) { Rails.root.join("tmp", "address_scan_seen.json") }
    around { |ex| saved = state.exist? ? state.read : nil; state.delete if state.exist?; ex.run; saved ? state.write(saved) : (state.delete if state.exist?) }

    it "sends everything as a starting list, then only what is new, and nothing when nothing is" do
      place("Unpinned", nil, nil, address: "2 Blank St")
      run = -> { Rake::Task["addresses:scan"].reenable; Rake::Task["addresses:scan"].invoke }
      expect { run.() }.to change { ActionMailer::Base.deliveries.size }.by(1)
      expect(ActionMailer::Base.deliveries.last.subject).to include("starting list")
      expect { run.() }.not_to change { ActionMailer::Base.deliveries.size }
      place("Another", nil, nil, address: "3 Blank St")
      expect { run.() }.to change { ActionMailer::Base.deliveries.size }.by(1)
      mail = ActionMailer::Base.deliveries.last
      expect(mail.subject).to include("1 new")
      expect(mail.body.to_s).to include("Another").and include("/en/address_checks")
      expect(mail.body.to_s).not_to include("Unpinned")
    end
  end
end
