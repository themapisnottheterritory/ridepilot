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
