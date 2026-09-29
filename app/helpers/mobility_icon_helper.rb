# A small icon in front of a rider's name when the trip records a mobility
# device other than Ambulatory (the trip's Mobility section, i.e. its
# ridership mobilities -- the customer's single mobility field is mostly an
# import default and isn't used). Wheelchair or scooter: a wheelchair; walker
# and the rest: a person with a cane. Hover for the exact devices.
module MobilityIconHelper
  NOT_A_NEED = ["Ambulatory", "Unknown"].freeze
  WHEELED = /wheelchair|scooter/i

  def trip_mobility_needs(trip)
    trip.ridership_mobilities.select { |m| m.capacity.to_i > 0 }
        .map { |m| m.mobility&.name }.compact.uniq - NOT_A_NEED
  end

  def mobility_icon(trip)
    needs = trip_mobility_needs(trip)
    return "".html_safe if needs.empty?
    icon = needs.any? { |n| n =~ WHEELED } ? "fa-wheelchair" : "fa-blind"
    content_tag(:span, class: "mobility-icon", title: needs.join(", "), "aria-label": "Mobility: #{needs.join(', ')}") do
      tag.i(class: "fas #{icon}", "aria-hidden": true)
    end
  end
end
