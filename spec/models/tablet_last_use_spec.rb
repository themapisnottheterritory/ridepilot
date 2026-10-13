require "rails_helper"

# Where a tablet was last used, and the inventory warnings (Tablets page, 2026-10-13).
RSpec.describe Tablet, type: :model do
  let(:tablet) { Tablet.create!(android_id: "lastuse1", number: 7, info: {}) }

  def ping(at, username: nil, battery: 90, charging: false)
    tablet.pings.create!(at: at, username: username, battery: battery, charging: charging)
  end

  describe "#last_use" do
    let(:user) { create(:user, username: "driver7") }
    let(:driver) { create(:driver, user: user) }
    let(:bus) { create(:vehicle, name: "1777") }
    let(:spare) { create(:vehicle, name: "1705") }

    it "names the bus and run the signed-in driver was on at the time" do
      day = Time.zone.now.change(hour: 12)
      create(:run, driver: driver, vehicle: spare, name: "UDR1", date: day.to_date,
             scheduled_start_time: day.change(hour: 6), scheduled_end_time: day.change(hour: 9))
      create(:run, driver: driver, vehicle: bus, name: "UDR3", date: day.to_date,
             scheduled_start_time: day.change(hour: 10), scheduled_end_time: day.change(hour: 17))
      ping(day - 2.hours, username: "driver7")
      ping(day, username: "driver7")
      ping(day + 5.minutes)   # signed out since: still the last use
      expect(tablet.last_use).to include(username: "driver7", driver: driver.name, run: "UDR3", bus: "1777")
      expect(tablet.last_use_label).to eq "bus 1777 · #{driver.name} · UDR3"
    end

    it "still names the driver when they had no run that day" do
      ping(Time.zone.now, username: "driver7")
      driver
      expect(tablet.last_use_label).to eq driver.name
    end

    it "is nil before anyone signs in" do
      ping(Time.zone.now)
      expect(tablet.last_use).to be_nil
    end
  end

  describe "#issues" do
    def texts = tablet.issues.map(&:last)

    it "warns about a security patch behind other tablets of its model, not a whole model's age" do
      old_patch = { "device" => { "securityPatch" => "2023-10-01" } }
      tablet.update!(model: "SM-T547U", info: old_patch)
      Tablet.create!(android_id: "peer", model: "SM-T547U", info: old_patch)
      expect(texts.join).not_to include("Security patch")            # the maker's last update: nothing to do per tablet
      Tablet.create!(android_id: "newer", model: "SM-T547U", info: { "device" => { "securityPatch" => "2024-02-01" } })
      Rails.cache.delete("tablets:newest_patches")
      expect(texts).to include("Security patch Oct 2023; other SM-T547U tablets have Feb 2024: run Software update")
      levels = Tablet.patch_levels
      expect(levels.map { |m, n, d, _| [m, n, d.to_s] }).to eq [["SM-T547U", 3, "2024-02-01"]]
    end

    it "warns when a shift started on a low battery that wasn't charging" do
      ping(1.hour.ago, battery: 20)                       # no one signed in yet
      ping(30.minutes.ago, username: "d", battery: 35)    # the shift's first report
      ping(10.minutes.ago, username: "d", battery: 80, charging: true)
      expect(texts).to include("Started today's shift at 35% battery, not charging")
    end

    it "doesn't warn when the shift started charging" do
      ping(30.minutes.ago, username: "d", battery: 35, charging: true)
      expect(texts.join).not_to include("Started")
    end

    it "warns about storage nearly full by share as well as by size" do
      tablet.update!(info: { "storage" => { "freeMB" => 2000, "totalMB" => 30000 } })
      expect(texts).to include("Storage nearly full: 2000 of 30000 MB free")
      tablet.update!(info: { "storage" => { "freeMB" => 9000, "totalMB" => 30000 } })
      expect(texts.join).not_to include("Storage")
    end

    it "notes a SIM change for two weeks" do
      report = ->(phone) { Tablet.record!(report: { "device" => { "androidId" => "simswap" }, "network" => { "phoneNumber" => phone } }, app: {}, ip: "10.99.0.17") }
      report.("3615551234")
      t = report.("3615559876")
      expect([t.phone_previous, t.phone_number]).to eq %w[3615551234 3615559876]
      expect(t.issues.map(&:last)).to include(a_string_matching(/SIM changed .*: was \(361\) 555-1234, now \(361\) 555-9876/))
      t.update!(phone_changed_at: 15.days.ago)
      expect(t.issues.map(&:last).join).not_to include("SIM changed")
      expect(report.("3615559876").phone_previous).to eq "3615551234"   # same number again: nothing new
    end
  end
end
