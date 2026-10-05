# How the map (Nominatim, OpenStreetMap) spells roads that people type in
# their own words. Shared by the address box (AddressesController#geocode_suggest)
# and Ask RidePilot's add-a-place card (SavedPlaceProposal), so they agree.
module AddressSpelling
  module_function

  # "1219 West State Highway 72" -> "1219 TX 72"; "Farm to Market Road 953" ->
  # "FM 953": the map names highways by route number, and a direction word is
  # not part of that name. A direction may come before the route number or
  # after it ("State Highway 72 W"); a "W" left behind turned "2010 TX 72 W"
  # into 2010 West State Highway 72 in Kenedy, 30 miles from the Cuero address
  # that was meant (Michelle, 2026-10-05).
  def route(text)
    text.to_s.gsub(/\b(?:(?:N|S|E|W|North|South|East|West)\.?\s+)?(?:State\s+)?(?:Highway|Hwy\.?|SH|TX)\s*-?\s*(\d+[A-Z]?)\b(?:\s+(?:N|S|E|W|North|South|East|West)\b\.?)?/i, 'TX \1')
        .gsub(/\b(?:Farm\s+to\s+Market(?:\s+Road)?|F\.?M\.?)\s*-?\s*(\d+)\b/i, 'FM \1')
        .squish
  end

  # A road known by its number: TX 72, FM 953, US 59, CR 105, Loop 463.
  # Addresses on these are often just outside a town's limit, where the map
  # gives them no town at all.
  NUMBERED_ROAD = /\b(?:TX|SH|FM|US|CR|RR|County\s+Road|State\s+Highway|Highway|Hwy|Loop|Spur|Farm\s+to\s+Market(?:\s+Road)?)\.?\s*-?\s*\d/i

  def numbered_road?(text)
    text.to_s.match?(NUMBERED_ROAD)
  end
end
