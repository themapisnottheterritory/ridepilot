# The town of a place, as a badge beside it (Phil, 2026-10-06: 30 saved-place
# names were used in more than one town -- Walmart, Dialysis, the senior
# center -- and a wrong pick sends a bus to the wrong town). Green when it's the
# rider's own town (their mailing address), amber when it's another, plain when
# there's no rider to compare with. Marked no-export, so a table's Download
# keeps the address text as it was (the town is already in it).
module TownBadgeHelper
  def town_badge(address, home = nil)
    return if address.nil? || address.coded_by_lat_lng?
    town = address.city.to_s.strip
    return if town.empty?
    home_town = home&.city.to_s.strip
    kind, title =
      if home_town.empty? then [nil, nil]
      elsif town.casecmp?(home_town) then ["home", "The rider's town"]
      else ["away", "Not the rider's town (#{home_town})"]
      end
    content_tag(:span, town, class: ["town-chip", kind, "no-export"].compact.join(" "), title: title)
  end
end
