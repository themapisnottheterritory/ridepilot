# The printable trip list (Trips > Print, 2026-10-08, for Michelle): the
# filtered trips grouped by run or by day, in the printed manifest's style,
# with a tick box and ruled space to write on.
module TripPrintHelper
  GROUPS = { "run" => "Run", "day" => "Day", "none" => "Time only" }.freeze

  # [[heading, trips], ...] in the order they print.
  def trip_print_groups(trips, group)
    case group
    when "none" then [[nil, trips]]
    when "day"  then trips.group_by { |t| t.pickup_time.to_date }.sort_by(&:first).map { |d, ts| [d, ts] }
    else
      trips.group_by { |t| t.run || trip_print_status(t) }
           .sort_by { |key, ts| [ts.first.pickup_time.to_date, key.is_a?(Run) ? 0 : 1, key.is_a?(Run) ? key.name.to_s : key, ts.first.pickup_time] }
    end
  end

  def trip_print_status(trip)
    return trip.run.name if trip.run
    return "Cab" if trip.cab
    return "Standby" if trip.is_stand_by
    "Not on a run"
  end

  # "Thursday, October 8, 2026", or "Oct 6 – Oct 9, 2026" for a range
  def trip_print_dates(trips, from, to)
    days = trips.map { |t| t.pickup_time.to_date }.uniq.sort
    first, last = days.first || from, days.last || to
    return first.strftime("%A, %B %-d, %Y") if first == last
    "#{first.strftime('%b %-d')} – #{last.strftime(first.year == last.year ? '%b %-d, %Y' : '%b %-d, %Y')}"
  end

  # What the Trips page filter is set to, in words, for the sheet's header.
  def trip_print_filters
    out = []
    if (c = Customer.find_by(id: session[:trips_customer_id]))
      out << "Rider: #{c.name}"
    end
    case session[:trips_status_id].to_s
    when "-2" then out << "Not on a run"
    when "-1" then out << "Cab"
    when /\A\d+\z/ then (r = Run.find_by(id: session[:trips_status_id])) && out << "Run: #{r.name}"
    end
    # Result and Funding are tick lists, all ticked ("Show All") by default:
    # only a narrower choice is a filter worth printing.
    results = trip_print_ticked(session[:trips_trip_result_id], TripResult::SHOW_ALL_ID)
    if results
      names = TripResult.where(id: results).order(:name).pluck(:name)
      names << "Pending" if results.include?(TripResult::UNSCHEDULED_ID)
      out << "Result: #{trip_print_list(names)}"
    end
    funding = trip_print_ticked(session[:trips_funding_source_id], FundingSource::SHOW_ALL_ID)
    out << "Funding: #{trip_print_list(FundingSource.where(id: funding).order(:name).pluck(:name))}" if funding
    days = session[:trips_days_of_week].to_s.split(",").map(&:to_i)
    out << "Days: #{days.map { |d| Date::ABBR_DAYNAMES[d] }.join(', ')}" if days.any? && days.size < 7
    out
  end

  # The ticked ids, or nil when nothing narrows the list (none, or Show All).
  def trip_print_ticked(value, show_all_id)
    ids = Array(value).reject(&:blank?).map(&:to_i)
    return nil if ids.empty? || ids.include?(show_all_id)
    ids
  end

  def trip_print_list(names)
    names.size > 4 ? "#{names.first(4).join(', ')} +#{names.size - 4} more" : names.join(", ")
  end
end
