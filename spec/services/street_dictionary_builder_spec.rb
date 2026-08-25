require 'rails_helper'

RSpec.describe StreetDictionaryBuilder do
  let(:builder) { described_class.new(logger: Logger.new(File::NULL)) }

  def entry(attrs = {})
    StreetDictionaryEntry.create!({
      raw_street: "E Virginia Ave", city: "Victoria", state: "TX", weight: 1
    }.merge(attrs))
  end

  describe "#collect" do
    # collect only sees geocoded addresses, so a live one has to have a point.
    def live_address(street, city)
      create(:address, address: street, city: city, state: "TX",
                       the_geom: Address.compute_geom(29.0, -97.0))
    end

    it "prunes entries for spellings no longer in the address book" do
      live_address("1010 McArthur Street", "Cuero")
      stale = entry(raw_street: "Macarthur St", city: "Cuero",
                    street: "McArthur Street", weight: 20)

      builder.collect

      expect(StreetDictionaryEntry.where(id: stale.id)).to be_empty
      expect(StreetDictionaryEntry.find_by(raw_street: "McArthur Street", city: "Cuero")).to be_present
    end

    it "refuses to prune when that would wipe most of the table" do
      # No live addresses at all: every entry looks stale, which is exactly the
      # shape of a broken collect. Deleting the table here would be the bug.
      5.times { |i| entry(raw_street: "Gone #{i} St", city: "Cuero") }

      expect { builder.collect }.not_to change(StreetDictionaryEntry, :count)
      expect(builder.stats[:prune_refused]).to eq(5)
    end
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
