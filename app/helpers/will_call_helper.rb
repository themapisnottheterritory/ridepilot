# "Will call" label next to a trip in the office lists: the rider calls when
# ready, so its pickup time is an estimate (trips.will_call).
module WillCallHelper
  def will_call_label(trip)
    return "".html_safe unless trip.try(:will_call)
    content_tag(:span, "Will call", class: "label will-call-label",
                title: "The rider calls when ready; the pickup time is an estimate")
  end
end
