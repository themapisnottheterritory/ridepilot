require "rails_helper"

RSpec.describe FareToken do
  let(:provider) { create(:provider) }
  let(:rider)    { create_rider(provider) }

  it "stores the UID in one canonical form" do
    t = FareToken.create!(provider: provider, customer: rider, kind: "rfid", uid: "04 a3:b2-c1 d9e6f0")
    expect(t.uid).to eq "04A3B2C1D9E6F0"
    expect(t.display_uid).to eq "04 A3 B2 C1 D9 E6 F0"
  end

  it "refuses the same UID twice while the first is live" do
    FareToken.create!(provider: provider, customer: rider, kind: "rfid", uid: "AABBCCDD")
    dup = FareToken.new(provider: provider, customer: create_rider(provider), kind: "rfid", uid: "aabbccdd")
    expect(dup).not_to be_valid
    expect(dup.errors[:uid].first).to match(/already issued/)
  end

  it "mints a UID and a serial for a QR code" do
    t = FareToken.create!(provider: provider, customer: rider, kind: "qr")
    expect(t.uid).to match(/\A[BCDFGHJKLMNPQRSTVWXZ][BCDFGHJKLMNPQRSTVWXZ2-9]{11}\z/)
    expect(t.serial).to eq "1001"
    t2 = FareToken.create!(provider: provider, customer: rider, kind: "rfid", uid: "01020304")
    expect(t2.serial).to eq "1002"
  end

  it "keeps a serial the office typed from the card face" do
    t = FareToken.create!(provider: provider, customer: rider, kind: "rfid", uid: "01020304", serial: " 77 ")
    expect(t.serial).to eq "77"
  end

  describe ".lookup" do
    it "finds by canonical hex, and by the decimal a differently configured reader would type" do
      t = FareToken.create!(provider: provider, customer: rider, kind: "rfid", uid: "04A3B2C1")
      expect(FareToken.lookup("04a3b2c1")).to eq t
      expect(FareToken.lookup("04 A3 B2 C1")).to eq t
      expect(FareToken.lookup(0x04A3B2C1.to_s)).to eq t
    end

    it "finds a decimal UID from its hex reading" do
      t = FareToken.create!(provider: provider, customer: rider, kind: "rfid", uid: "0009350016")
      expect(FareToken.lookup("0009350016")).to eq t
      expect(FareToken.lookup(9350016.to_s(16))).to eq t
    end

    it "returns nil for nothing or an unknown card" do
      expect(FareToken.lookup("")).to be_nil
      expect(FareToken.lookup("DEADBEEF")).to be_nil
    end
  end

  it "rejects a rider from another provider" do
    other = create(:provider)
    t = FareToken.new(provider: other, customer: rider, kind: "rfid", uid: "01020304")
    expect(t).not_to be_valid
    expect(t.errors[:customer]).to be_present
  end
end
