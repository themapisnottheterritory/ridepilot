require 'rails_helper'

RSpec.describe StreetDictionaryEntry, type: :model do
  describe ".split_house_number" do
    it "separates a leading house number from the street" do
      expect(described_class.split_house_number("1404 E Virginia Ave")).to eq(["1404", "E Virginia Ave"])
    end

    it "keeps alphanumeric house numbers together" do
      expect(described_class.split_house_number("12B Main St")).to eq(["12B", "Main St"])
    end

    it "returns a nil house number when the street does not start with one" do
      expect(described_class.split_house_number("Citizen Drive")).to eq([nil, "Citizen Drive"])
    end

    it "drops keyword-introduced unit numbers" do
      expect(described_class.split_house_number("5609 John Stockbauer Dr APT 31102"))
        .to eq(["5609", "John Stockbauer Dr"])
    end

    # These are the strings that made the dictionary underperform doing nothing:
    # left attached, the trailing code stops the address geocoding.
    it "drops bare trailing unit codes that carry no keyword" do
      expect(described_class.split_house_number("2309 Leary Ln NO6")).to eq(["2309", "Leary Ln"])
      expect(described_class.split_house_number("410 Village Dr 94")).to eq(["410", "Village Dr"])
      expect(described_class.split_house_number("217 W 7Th St 10")).to eq(["217", "W 7Th St"])
    end

    it "does not mistake a street name's own trailing token for a unit" do
      expect(described_class.split_house_number("677 Ave F")).to eq(["677", "Ave F"])
    end
  end

  describe ".normalize" do
    it "expands directionals and street types so abbreviations match" do
      expect(described_class.normalize("E Virginia Ave")).to eq("east virginia avenue")
      expect(described_class.normalize("N Depot St")).to eq("north depot street")
    end

    it "normalizes what the user types to the same key as what we stored" do
      expect(described_class.normalize("E Vir")).to eq("east vir")
      expect(described_class.normalize("East Virginia Avenue")).to start_with(described_class.normalize("E Vir"))
    end

    it "strips punctuation and collapses whitespace" do
      expect(described_class.normalize("  N.  Fort  St.,  ")).to eq("north fort street")
    end
  end

  describe ".complete" do
    let!(:virginia) do
      create_entry(street: "East Virginia Avenue", city: "Victoria", weight: 3)
    end
    let!(:vine) do
      create_entry(street: "East Vine Street", city: "Victoria", weight: 50)
    end
    let!(:unresolved) do
      described_class.create!(raw_street: "E Vista", city: "Victoria", state: "TX", weight: 99)
    end

    def create_entry(street:, city:, weight:)
      described_class.create!(
        raw_street: street, city: city, state: "TX", weight: weight,
        street: street, search_key: described_class.normalize(street),
        resolved_at: Time.current
      )
    end

    it "completes from a short prefix" do
      expect(described_class.complete("E Vir")).to include(virginia)
    end

    it "ranks more-used streets first" do
      expect(described_class.complete("E Vi").first).to eq(vine)
    end

    it "never suggests an entry that failed to canonicalize" do
      expect(described_class.complete("E Vis")).not_to include(unresolved)
    end

    it "matches across a space the user inserted" do
      # Staff split these names unpredictably: the Cuero addresses alone carried
      # "Mc Arthur", "Mac Arthur", "Macarthur" and "McArthur".
      mcarthur = create_entry(street: "McArthur Street", city: "Cuero", weight: 47)
      expect(described_class.complete("Mc Art")).to include(mcarthur)
      expect(described_class.complete("McArt")).to include(mcarthur)
    end

    it "returns nothing for a fragment that is too short to be meaningful" do
      expect(described_class.complete("E")).to be_empty
    end

    it "treats LIKE metacharacters in user input as literals" do
      expect { described_class.complete("100%_") }.not_to raise_error
      expect(described_class.complete("100%_")).to be_empty
    end
  end
end
