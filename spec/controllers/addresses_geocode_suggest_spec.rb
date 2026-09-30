require "rails_helper"

RSpec.describe AddressesController, type: :controller do
  login_admin_as_current_user

  describe "GET #geocode_suggest" do
    # Carries the typed house number, so the controller does not spend a second pass.
    let(:hit) { [{ "place_id" => 1, "display_name" => "1404 E Virginia Ave, Bay City", "address" => { "house_number" => "1404" } }] }

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

  # Kelly, 2026-09-30: "1219 West State Highway 72" offered only the road in
  # Kenedy; the map calls the Cuero stretch "TX 72".
  describe "highways and a town" do
    let(:kenedy)  { { "place_id" => 1, "lat" => "28.8189", "lon" => "-97.8486", "address" => { "road" => "West State Highway 72", "city" => "Kenedy" } } }
    let(:cuero)   { { "place_id" => 2, "lat" => "29.0886", "lon" => "-97.3147", "address" => { "house_number" => "1219", "road" => "TX 72", "county" => "DeWitt County" } } }
    let(:yorktown) { { "place_id" => 3, "lat" => "28.9956", "lon" => "-97.4838", "address" => { "house_number" => "1219", "road" => "TX 72", "city" => "Yorktown" } } }

    it "asks again in the map's route-number spelling when the typed spelling found no house number" do
      allow(controller).to receive(:nominatim_suggest).and_return([])
      allow(controller).to receive(:nominatim_suggest).with(q: "1219 West State Highway 72").and_return([kenedy])
      expect(controller).to receive(:nominatim_suggest).with(q: "1219 TX 72").and_return([yorktown, cuero])
      get :geocode_suggest, params: { q: "1219 West State Highway 72" }
      ids = JSON.parse(response.body).map { |r| r["place_id"] }
      expect(ids.first(2)).to contain_exactly(2, 3)
      expect(ids).to include(1)
    end

    it "keeps the answers near the town typed, nearest first" do
      allow(controller).to receive(:nominatim_suggest).and_return([])
      allow(controller).to receive(:nominatim_suggest).with(q: "1219 TX 72").and_return([kenedy, yorktown, cuero])
      allow(controller).to receive(:nominatim_suggest).with(city: "Cuero", state: "TX").and_return([{ "lat" => "29.0938", "lon" => "-97.2890" }])
      get :geocode_suggest, params: { q: "1219 West State Highway 72, Cuero" }
      expect(JSON.parse(response.body).map { |r| r["place_id"] }).to eq [2, 3]   # Kenedy is 40 miles off
    end
  end

end
