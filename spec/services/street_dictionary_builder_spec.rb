require 'rails_helper'

RSpec.describe StreetDictionaryBuilder do
  let(:builder) { described_class.new(logger: Logger.new(File::NULL)) }

  def entry(attrs = {})
    StreetDictionaryEntry.create!({
      raw_street: "E Virginia Ave", city: "Victoria", state: "TX", weight: 1
    }.merge(attrs))
  end

  describe "#canonicalize" do
    context "retry interval" do
      # The nightly rebuild must stay proportional to the number of NEW streets.
      # About a quarter of collected streets never resolve; retrying all of them
      # every night cost thousands of geocoder requests and ~8 minutes to learn
      # nothing, which is what this interval exists to prevent.
      it "skips entries that failed within the retry window" do
        entry(last_attempted_at: 2.days.ago)
        expect(builder).not_to receive(:lookup_road)

        builder.canonicalize
      end

      it "retries entries that failed long enough ago" do
        entry(last_attempted_at: (described_class::RETRY_AFTER + 1.day).ago)
        allow(builder).to receive(:lookup_road).and_return(nil)

        expect(builder).to receive(:lookup_road).once
        builder.canonicalize
      end

      it "always tries an entry that has never been attempted" do
        entry(last_attempted_at: nil)
        allow(builder).to receive(:lookup_road).and_return(nil)

        expect(builder).to receive(:lookup_road).once
        builder.canonicalize
      end

      it "ignores the interval when asked for a full sweep" do
        entry(last_attempted_at: 1.hour.ago)
        allow(builder).to receive(:lookup_road).and_return(nil)

        expect(builder).to receive(:lookup_road).once
        builder.canonicalize(retry_all: true)
      end
    end

    it "records the attempt whether or not it resolved" do
      e = entry(last_attempted_at: nil)
      allow(builder).to receive(:lookup_road).and_return(nil)

      expect { builder.canonicalize }
        .to change { e.reload.attempts }.from(0).to(1)
      expect(e.last_attempted_at).to be_present
      expect(e.street).to be_nil
    end

    it "stores the canonical name, not our own spelling" do
      e = entry(raw_street: "E Virginia St", last_attempted_at: nil)
      allow(builder).to receive(:lookup_road).and_return("East Virginia Avenue")

      builder.canonicalize
      e.reload

      expect(e.street).to eq("East Virginia Avenue")
      expect(e.search_key).to eq(StreetDictionaryEntry.normalize("East Virginia Avenue"))
      expect(e.resolved_at).to be_present
    end

    it "leaves already-resolved entries alone" do
      e = entry(street: "East Virginia Avenue", resolved_at: 1.year.ago, last_attempted_at: nil)
      expect(builder).not_to receive(:lookup_road)

      builder.canonicalize
      expect(e.reload.street).to eq("East Virginia Avenue")
    end
  end
end
