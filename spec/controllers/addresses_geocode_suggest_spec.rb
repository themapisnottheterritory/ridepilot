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

    # Michelle, 2026-10-05: a place name in front and the direction after the
    # route number. The "W" alone would have matched Kenedy.
    it "searches from the house number and drops a direction after the route number" do
      allow(controller).to receive(:nominatim_suggest).and_return([])
      expect(controller).to receive(:nominatim_suggest).with(q: "1219 TX 72").and_return([kenedy, yorktown, cuero])
      allow(controller).to receive(:nominatim_suggest).with(city: "Cuero", state: "TX").and_return([{ "lat" => "29.0938", "lon" => "-97.2890" }])
      get :geocode_suggest, params: { q: "Diane's Hair Salon 1219 State Highway 72 W, Cuero, TX, 77954-5102" }
      expect(JSON.parse(response.body).map { |r| r["place_id"] }.first).to eq 2
    end

    it "leaves a street with a number in its name alone" do
      expect(controller.send(:route_spelling, "1219 W SH 72")).to eq "1219 TX 72"
      expect(controller.send(:route_spelling, "1219 State Highway 72 West")).to eq "1219 TX 72"
      strip = ->(t) { controller.send(:strip_leading_name, t) }
      expect(strip.("Diane's Hair Salon 2010 State Highway 72 W")).to eq "2010 State Highway 72 W"
      expect(strip.("Highway 59 Frontage 1200")).to eq "Highway 59 Frontage 1200"
      expect(strip.("CR 181 Victoria")).to eq "CR 181 Victoria"
      expect(strip.("PO Box 12 Victoria")).to eq "PO Box 12 Victoria"
      expect(strip.("1404 E Virginia Ave")).to eq "1404 E Virginia Ave"
    end
  end

  # Bobbie, 2026-09-30: "202 E Second St Bloomington" found nothing; the map
  # spells it "2nd Street East", so she booked by latitude/longitude.
  describe "spelled-out numbered streets" do
    let(:bloomington) { { "place_id" => 7, "lat" => "28.6461", "lon" => "-96.8964", "address" => { "house_number" => "202", "road" => "2nd Street East", "city" => "Bloomington" } } }

    it "asks again with the number when Second St found nothing" do
      allow(controller).to receive(:nominatim_suggest).and_return([])
      expect(controller).to receive(:nominatim_suggest).with(q: "202 E 2nd St Bloomington TX 77951").and_return([bloomington])
      get :geocode_suggest, params: { q: "202 E Second St Bloomington TX 77951" }
      expect(JSON.parse(response.body).map { |r| r["place_id"] }).to eq [7]
    end

    it "only respells a word that names a street" do
      expect(controller.send(:ordinal_spelling, "100 First Baptist Church Rd")).to eq "100 First Baptist Church Rd"
      expect(controller.send(:ordinal_spelling, "12 Second Chance Ln")).to eq "12 Second Chance Ln"
      expect(controller.send(:ordinal_spelling, "305 W TWELFTH STREET")).to eq "305 W 12th STREET"
      expect(controller.send(:ordinal_spelling, "9 First Ave. N")).to eq "9 1st Ave. N"
    end

    it "keeps an answer the typed spelling already found" do
      found = { "place_id" => 8, "address" => { "house_number" => "202", "road" => "Second Street" } }
      allow(controller).to receive(:nominatim_suggest).and_return([])
      allow(controller).to receive(:nominatim_suggest).with(q: "202 Second St").and_return([found])
      expect(controller).not_to receive(:nominatim_suggest).with(q: "202 2nd St")
      get :geocode_suggest, params: { q: "202 Second St" }
      expect(JSON.parse(response.body).map { |r| r["place_id"] }).to eq [8]
    end
  end

end
