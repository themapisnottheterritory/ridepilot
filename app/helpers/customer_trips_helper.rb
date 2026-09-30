# Short words for a customer's trips on the Trips panel and the hover card.
module CustomerTripsHelper
  # "Home", "Citizens Medical Center", or the street address
  def trip_place_label(address)
    return "?" unless address
    address.name.presence || address.address.presence || address.try(:address_text).to_s
  end

  # what's happening with the trip, in a word or two
  def trip_state_badge(trip)
    if trip.trip_result
      done = trip.trip_result.code == "COMP"
      content_tag(:span, trip.trip_result.name, class: "ct-badge #{done ? 'done' : 'off'}")
    elsif trip.run
      content_tag(:span, trip.run.name, class: "ct-badge run", title: "On run #{trip.run.name}")
    else
      content_tag(:span, "Not on a run", class: "ct-badge wait")
    end
  end
end
