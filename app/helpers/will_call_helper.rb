# "Will call" label next to a trip in the office lists: the rider calls when
# ready, so its pickup time is an estimate (trips.will_call).
module WillCallHelper
  def will_call_label(trip)
    return "".html_safe unless trip.try(:will_call)
    content_tag(:span, "Will call", class: "label will-call-label",
                title: "The rider calls when ready; the pickup time is an estimate")
  end

  # On a will-call pickup in today's Dispatch: "Ready" sends the driver the
  # rider's details (Trip#will_call_ready!); afterwards it says when.
  def will_call_ready_control(trip, itin, run)
    return "".html_safe unless trip.try(:will_call) && itin.leg_flag == 1 && run && trip.date == Time.zone.today
    content_tag(:span, class: "will-call-ready", id: "will-call-ready-#{trip.id}") do
      if trip.will_call_ready_at
        content_tag(:span, "Ready #{trip.will_call_ready_at.in_time_zone.strftime('%-l:%M')}", class: "label label-success",
                    title: "Sent to the driver")
      elsif can?(:edit, trip)
        link_to("Ready", trip_will_call_ready_path(trip), remote: true, method: :post, class: "btn btn-xs btn-primary",
                title: "The rider called: tell the driver they're ready",
                data: { confirm: "Tell the driver #{trip.customer.try(:name)} is ready?" })
      else
        "".html_safe
      end
    end
  end
end
