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

  # Michelle, 2026-10-06: "33 Seakist Rd Port Lavaca, TX 77979" was "not
  # recognized", and a replay of every search since Sep 21 found more like it:
  # the map reads "33" as Highway 33, files Seakist Road under Calhoun County,
  # and answered other towns entirely (Friendswood for Port Lavaca). These stub
  # the map itself (nominatim_fetch) so the near-town filter runs as it does live.
  describe "keeping to the town typed" do
    let(:towns) { { "port lavaca" => { name: "Port Lavaca", n: 1537, lat: 28.615, lon: -96.628 },
                    "bloomington" => { name: "Bloomington", n: 780, lat: 28.648, lon: -96.893 },
                    "victoria"    => { name: "Victoria", n: 11269, lat: 28.813, lon: -96.990 } } }
    let(:seakist) { { "place_id" => 9, "lat" => "28.6734", "lon" => "-96.6448", "display_name" => "Seakist Road, Calhoun County, Texas, United States",
                      "address" => { "road" => "Seakist Road", "county" => "Calhoun County", "state" => "Texas" } } }
    let(:bexar)   { { "place_id" => 10, "lat" => "29.40", "lon" => "-98.50", "display_name" => "Seakist Road, Bexar County, Texas",
                      "address" => { "road" => "Seakist Road", "county" => "Bexar County" } } }
    let(:friendswood) { { "place_id" => 11, "lat" => "29.529", "lon" => "-95.201", "display_name" => "332, Independence Drive, Friendswood, Galveston County",
                          "address" => { "house_number" => "332", "road" => "Independence Drive", "town" => "Friendswood" } } }
    let(:port_lavaca) { { "place_id" => 12, "lat" => "28.632", "lon" => "-96.615", "display_name" => "332, Independence Drive, Port Lavaca, Calhoun County",
                          "address" => { "house_number" => "332", "road" => "Independence Drive", "town" => "Port Lavaca" } } }

    before do
      allow(TownCentres).to receive(:all).and_return(towns)
      allow(controller).to receive(:nominatim_fetch).and_return([])
      allow(PlaceSearch).to receive(:address).and_return([])
    end

    it "finds the street by name near the town typed without a comma, with the number, town and zip typed" do
      allow(controller).to receive(:nominatim_fetch).with(hash_including(street: "Seakist Rd")).and_return([seakist, bexar])
      get :geocode_suggest, params: { q: "33 Seakist Rd Port Lavaca, TX 77979" }
      r = JSON.parse(response.body)
      expect(r.map { |x| x["place_id"] }).to eq [9]                       # the Seakist Road 300 miles off is dropped
      expect(r.first["address"]).to include("house_number" => "33", "road" => "Seakist Road", "town" => "Port Lavaca", "postcode" => "77979")
      expect(r.first["display_name"]).to start_with("33 Seakist Road, Port Lavaca, Calhoun County")
    end

    it "drops a house in another town as it arrives, so the right one is still looked for" do
      allow(controller).to receive(:nominatim_fetch).with(hash_including(q: "332 Independence Drive, Port Lavaca, TX 77979")).and_return([friendswood])
      allow(controller).to receive(:nominatim_fetch).with(hash_including(street: "332 Independence Drive, Port Lavaca, TX 77979")).and_return([port_lavaca])
      get :geocode_suggest, params: { q: "332 Independence Drive, Port Lavaca, TX 77979" }
      expect(JSON.parse(response.body).map { |x| x["place_id"] }).to eq [12]
    end

    it "drops an answer that names another of our towns, and a house on another street" do
      towns["el campo"] = { name: "El Campo", n: 57, lat: 29.197, lon: -96.270 }
      towns["bay city"] = { name: "Bay City", n: 1490, lat: 28.983, lon: -95.969 }
      el_campo = { "place_id" => 15, "lat" => "29.19", "lon" => "-96.27", "address" => { "house_number" => "800", "road" => "Avenue F", "town" => "El Campo" } }
      james = { "place_id" => 16, "lat" => "28.98", "lon" => "-95.97", "address" => { "house_number" => "800", "road" => "James Avenue", "city" => "Bay City" } }
      bay_city = { "place_id" => 17, "lat" => "28.98", "lon" => "-95.96", "address" => { "house_number" => "800", "road" => "Avenue F", "city" => "Bay City" } }
      allow(controller).to receive(:nominatim_fetch).and_return([el_campo, james, bay_city])
      get :geocode_suggest, params: { q: "800 Ave F, Bay City, TX 77414" }
      expect(JSON.parse(response.body).map { |x| x["place_id"] }).to eq [17]
    end

    it "keeps a far answer when nothing near was found and no town was typed" do
      houston_va = { "place_id" => 18, "lat" => "29.70", "lon" => "-95.39", "address" => { "house_number" => "2002", "road" => "Holcombe Boulevard", "city" => "Houston" } }
      allow(controller).to receive(:nominatim_fetch).and_return([houston_va])
      get :geocode_suggest, params: { q: "2002 holcombe blvd" }
      expect(JSON.parse(response.body).map { |x| x["place_id"] }).to eq [18]
    end

    it "matches a street still being typed, and drops an answer with no road" do
      virginia = { "place_id" => 19, "lat" => "28.62", "lon" => "-96.63", "address" => { "house_number" => "701", "road" => "North Virginia Street", "town" => "Port Lavaca" } }
      pipeline = { "place_id" => 20, "lat" => "28.62", "lon" => "-96.63", "address" => { "town" => "Port Lavaca" } }
      allow(controller).to receive(:nominatim_fetch).and_return([pipeline, virginia])
      get :geocode_suggest, params: { q: "701 n vIR" }
      expect(JSON.parse(response.body).map { |x| x["place_id"] }).to eq [19]
    end

    it "reads the map's own label edited, without taking the county for the town" do
      towns["matagorda"] = { name: "Matagorda", n: 16, lat: 28.695, lon: -95.970 }
      towns["bay city"] = { name: "Bay City", n: 1490, lat: 28.983, lon: -95.969 }
      palm = { "place_id" => 21, "lat" => "28.99", "lon" => "-95.97", "address" => { "house_number" => "1900", "road" => "Palm Village Boulevard", "city" => "Bay City" } }
      allow(controller).to receive(:nominatim_fetch).with(hash_including(q: "1900 Palm Village Boulevard, Bay City, 77414")).and_return([palm])
      get :geocode_suggest, params: { q: "1900, Palm Village Boulevard, Bay City, Matagorda County, Texas, 77414, United States" }
      expect(JSON.parse(response.body).map { |x| x["place_id"] }).to eq [21]
    end

    it "takes a town in the street's name for the street" do
      towns["shiner"] = { name: "Shiner", n: 305, lat: 29.430, lon: -97.172 }
      towns["yoakum"] = { name: "Yoakum", n: 1248, lat: 29.289, lon: -97.149 }
      old_shiner = { "place_id" => 22, "lat" => "29.30", "lon" => "-97.15", "address" => { "house_number" => "900", "road" => "Old Shiner Road", "city" => "Yoakum" } }
      allow(controller).to receive(:nominatim_fetch).and_return([old_shiner])
      get :geocode_suggest, params: { q: "900 old shiner" }
      expect(JSON.parse(response.body).map { |x| x["place_id"] }).to eq [22]
    end

    it "keeps a town that starts a place's name for the name" do
      towns["matagorda"] = { name: "Matagorda", n: 16, lat: 28.695, lon: -95.970 }
      towns["bay city"] = { name: "Bay City", n: 1490, lat: 28.983, lon: -95.969 }
      hospital = { "place_id" => 23, "lat" => "28.98", "lon" => "-95.96", "display_name" => "Matagorda Regional Medical Center, 104, 7th Street, Bay City",
                   "address" => { "house_number" => "104", "road" => "7th Street", "city" => "Bay City" } }
      allow(controller).to receive(:nominatim_fetch).and_return([hospital])
      get :geocode_suggest, params: { q: "Matagorda Regional Medical Center" }
      expect(JSON.parse(response.body).map { |x| x["place_id"] }).to eq [23]
    end

    it "never keeps an answer outside Texas" do
      north_dakota = { "place_id" => 24, "lat" => "48.80", "lon" => "-101.02", "address" => { "house_number" => "1402", "road" => "Highway 5 Northwest" } }
      allow(controller).to receive(:nominatim_fetch).and_return([north_dakota])
      get :geocode_suggest, params: { q: "1402 US Highway 5" }
      expect(JSON.parse(response.body)).to eq []
    end

    it "keeps to a town typed misspelled" do
      austin = { "place_id" => 13, "lat" => "30.27", "lon" => "-97.74", "address" => { "house_number" => "219", "road" => "West 7th Street" } }
      bloomington = { "place_id" => 14, "lat" => "28.65", "lon" => "-96.89", "address" => { "house_number" => "219", "road" => "West 7th Street" } }
      allow(controller).to receive(:nominatim_fetch).and_return([austin, bloomington])
      get :geocode_suggest, params: { q: "219 W 7th St, Bloominton TX" }
      expect(JSON.parse(response.body).map { |x| x["place_id"] }).to eq [14]
    end

    it "asks Azure Maps for a finished address the map doesn't have, and puts the exact house first" do
      lucas = { "place_id" => "azure-1", "source" => "azure", "lat" => "28.7", "lon" => "-96.7", "display_name" => "26 Lucas Lane, Port Lavaca, TX 77979 (Azure Maps)",
                "address" => { "house_number" => "26", "road" => "Lucas Lane", "town" => "Port Lavaca" } }
      expect(PlaceSearch).to receive(:address).with(text: "26 Lucas Lane, Port Lavaca, TX 77979", house_number: "26", near: hash_including(name: "Port Lavaca")).and_return([lucas])
      get :geocode_suggest, params: { q: "26 Lucas Lane, Port Lavaca, TX 77979" }
      expect(JSON.parse(response.body).first["place_id"]).to eq "azure-1"
    end

    it "doesn't ask Azure Maps while the address is still being typed" do
      expect(PlaceSearch).not_to receive(:address)
      get :geocode_suggest, params: { q: "26 Lucas La" }
    end

    it "tidies how staff type addresses" do
      tidy = ->(t) { controller.send(:tidy_typed_address, t) }
      expect(tidy.("Day N Night Medical Supply, 2007 E Red River St, Victoria")).to eq "2007 E Red River St, Victoria"
      expect(tidy.("1300Captain Albert Martin Trl")).to eq "1300 Captain Albert Martin Trl"
      expect(tidy.("311 East Mockingbird LaneVictoria, TX")).to eq "311 East Mockingbird Lane Victoria, TX"
      expect(tidy.("709 E Rio GrandeAPT 1")).to eq "709 E Rio Grande APT 1"
      expect(tidy.("803-A Indianola")).to eq "803 Indianola"
      expect(tidy.("100 N Main St")).to eq "100 N Main St"
      expect(tidy.("1200 A Street")).to eq "1200 A Street"
      expect(tidy.("11840 FM957")).to eq "11840 FM 957"
      expect(tidy.("8289 FMn 466")).to eq "8289 FM 466"
      expect(tidy.("1219 TX-72, Cuero")).to eq "1219 TX 72, Cuero"
      expect(tidy.("80 Private Rd 1032, Hallettsville")).to eq "80 Private Road 1032, Hallettsville"
      expect(tidy.("8 Pvt RD 1192")).to eq "8 Private Road 1192"
      expect(tidy.("80 PR1032")).to eq "80 Private Road 1032"
      expect(tidy.("1102 McDonald St")).to eq "1102 McDonald St"
    end
  end
end
