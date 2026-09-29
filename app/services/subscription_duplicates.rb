# A rider's other subscriptions that could be the one being saved, so the
# subscription form can ask before a second copy goes in (2026-09-29: five
# riders had two identical templates, each making a duplicate trip every day).
#
# A match: same rider, the date ranges overlap, at least one weekday in common,
# and either the same pickup and drop-off addresses or a pickup time within
# NEAR of each other. A ride-home subscription (addresses swapped, hours later)
# is not a match.
class SubscriptionDuplicates
  DAYS = %w[sundays mondays tuesdays wednesdays thursdays fridays saturdays].freeze
  NEAR = 60 # minutes

  def initialize(params, provider_id)
    @params = params
    @provider_id = provider_id
  end

  def matches
    return [] if @params[:customer_id].blank?
    days = DAYS.each_index.select { |i| checked?(@params["repeats_#{DAYS[i]}"]) }
    return [] if days.empty?

    starts = parse_date(@params[:start_date]) || Time.zone.today
    ends = parse_date(@params[:end_date])
    minutes = minutes_of_day(@params[:pickup_time])
    route = route_key(Address.find_by(id: @params[:pickup_address_id]), Address.find_by(id: @params[:dropoff_address_id]))

    scope = RepeatingTrip.active.where(customer_id: @params[:customer_id], provider_id: @provider_id)
    scope = scope.where.not(id: @params[:id]) if @params[:id].present?
    scope.includes(:pickup_address, :dropoff_address).order(:pickup_time).select do |rt|
      dates_overlap?(rt, starts, ends) && (weekdays(rt) & days).any? &&
        ((route && route_key(rt.pickup_address, rt.dropoff_address) == route) ||
         (minutes && rt.pickup_time && (minutes_of_day(rt.pickup_time) - minutes).abs <= NEAR))
    end.map { |rt| as_json(rt) }
  end

  private

  def checked?(value)
    Array(value).last.to_s.in?(%w[1 true])
  end

  def weekdays(rt)
    DAYS.each_index.select { |i| rt.public_send("repeats_#{DAYS[i]}") }
  end

  def dates_overlap?(rt, starts, ends)
    (ends.nil? || rt.start_date.nil? || rt.start_date.to_date <= ends) &&
      (rt.end_date.nil? || rt.end_date.to_date >= starts)
  end

  # street and city, so two saved copies of the same place still match
  def route_key(pickup, dropoff)
    return nil unless pickup && dropoff
    [pickup, dropoff].map { |a| "#{a.address} #{a.city}".downcase.gsub(/[^a-z0-9]/, "") }
  end

  def minutes_of_day(value)
    time = value.is_a?(String) ? (Time.zone.parse(value) rescue nil) : value&.in_time_zone
    time && time.hour * 60 + time.min
  end

  def parse_date(value)
    Date.parse(value.to_s) if value.present?
  rescue ArgumentError
    nil
  end

  def as_json(rt)
    names = %w[Sun Mon Tue Wed Thu Fri Sat]
    {
      id: rt.id,
      days: weekdays(rt).map { |i| names[i] }.join(", "),
      pickup_time: rt.pickup_time&.in_time_zone&.strftime("%-l:%M %p"),
      pickup: rt.pickup_address&.then { |a| a.name.presence || a.address },
      dropoff: rt.dropoff_address&.then { |a| a.name.presence || a.address },
      dates: [rt.start_date&.strftime("%-m/%-d/%Y"), rt.end_date ? rt.end_date.strftime("%-m/%-d/%Y") : "no end date"].compact.join(" to ")
    }
  end
end
