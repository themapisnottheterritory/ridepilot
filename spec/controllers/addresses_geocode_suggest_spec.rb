require "rails_helper"

RSpec.describe AddressesController, type: :controller do
  login_admin_as_current_user

  describe "GET #geocode_suggest" do
    let(:hit) { [{ "place_id" => 1, "display_name" => "somewhere" }] }

    def suggest(term)
      get :geocode_suggest, params: { q: term, format: :json }
    end

    it "does not call the geocoder for a fragment below the minimum length" do
      expect(controller).not_to receive(:nominatim_suggest)
      suggest("ab")
      expect(JSON.parse(response.body)).to eq([])
    end

    it "returns free-text results without falling back" do
      expect(controller).to receive(:nominatim_suggest).with(q: "1404 E Virginia Ave").and_return(hit)
      expect(controller).not_to receive(:street_dictionary_suggest)

      suggest("1404 E Virginia Ave")
      expect(JSON.parse(response.body)).to eq(hit)
    end

    it "falls back to structured search when free text finds nothing" do
      allow(controller).to receive(:nominatim_suggest).with(hash_including(:q)).and_return([])
      expect(controller).to receive(:nominatim_suggest)
        .with(street: "1404 E Virginia", state: AddressesController::NOMINATIM_FALLBACK_STATE)
        .and_return(hit)

      suggest("1404 E Virginia")
      expect(JSON.parse(response.body)).to eq(hit)
    end

    context "when neither geocoder pass matches" do
      let!(:entry) do
        StreetDictionaryEntry.create!(
          raw_street: "E Virginia Ave", city: "Victoria", state: "TX", weight: 5,
          street: "East Virginia Avenue",
          search_key: StreetDictionaryEntry.normalize("East Virginia Avenue"),
          resolved_at: Time.current
        )
      end

      it "completes the street from the dictionary and geocodes the result" do
        allow(controller).to receive(:nominatim_suggest).with(hash_including(:q)).and_return([])
        allow(controller).to receive(:nominatim_suggest)
          .with(hash_including(state: "TX", city: nil)).and_return([])
        allow(controller).to receive(:nominatim_suggest)
          .with(street: "1404 E Vir", state: "TX").and_return([])

        # The point of the whole feature: a partial street Nominatim cannot
        # match becomes a complete, correctly-typed one that it can.
        expect(controller).to receive(:nominatim_suggest)
          .with(street: "1404 East Virginia Avenue", city: "Victoria", state: "TX")
          .and_return(hit)

        suggest("1404 E Vir")
        expect(JSON.parse(response.body)).to eq(hit)
      end

      it "returns nothing when the fragment matches no known street" do
        allow(controller).to receive(:nominatim_suggest).and_return([])

        suggest("1404 Zzz")
        expect(JSON.parse(response.body)).to eq([])
      end
    end
  end
end
