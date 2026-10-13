# "Fix from paper" (Philz 2026-10-13): dispatch puts a run right from the paper
# manifest when the tablet missed it -- a driver on paper as a fall-back, a dead
# tablet, stops tapped late. One form: the run's bus, actual start and end and
# odometers; each stop's arrived and done times; each trip's result. Reports
# (Run Log, Vehicle Summary) then count the run like a tapped one.
#
# Typed stop times are marked on the stop (times_typed_by / times_typed_at), so
# a typed time is never mistaken for a tablet tap. The run's own changes are
# paper-trailed as usual. All or nothing: one bad field saves nothing.
#
#   fix = RunPaperFix.new(run, params[:paper], user: current_user)
#   fix.save   # => true, or false with fix.errors ["Tina Mcneese pick-up: done before arrived", ...]
class RunPaperFix
  RUN_FIELDS = %w[vehicle_id start_odometer end_odometer].freeze

  attr_reader :run, :errors, :changed_stops

  def initialize(run, form, user:)
    @run = run
    @form = (form || {}).to_h.with_indifferent_access
    @user = user
    @errors = []
    @changed_stops = 0
  end

  # The run's stops in order, with their trips (the page and the save use the same list).
  def stops
    @stops ||= Itinerary.where(run_id: run.id).includes(trip: [:customer, :trip_result], address: []).to_a
                        .sort_by { |i| [i.time || i.eta || run.scheduled_end_time || Time.current, i.leg_flag.to_i, i.id] }
  end

  def save
    apply_run
    apply_stops
    apply_results
    check_order
    return false if errors.any?
    Run.transaction do
      @run.save(validate: false) if @run.changed?   # validated below, with the clash named
      @dirty_stops.each(&:save!)
      # as Dispatch's result menu saves a result: the trip's other rules are about booking
      @dirty_trips.each { |t| t.save(validate: false); t.post_process_trip_result_changed!(@user) }
    end
    true
  rescue ActiveRecord::RecordInvalid => e
    errors << e.record.errors.full_messages.to_sentence
    false
  end

  # "13:05" on the run's day, nil for blank, :bad for anything else.
  def at(text)
    s = text.to_s.strip
    return nil if s.empty?
    m = s.match(/\A(\d{1,2}):(\d{2})\z/) or return :bad
    h, mi = m[1].to_i, m[2].to_i
    return :bad if h > 23 || mi > 59
    run.date.in_time_zone.change(hour: h, min: mi)
  end

  def self.hm(t)
    t&.in_time_zone&.strftime("%H:%M")
  end

  private

  def apply_run
    r = @form[:run] || {}
    RUN_FIELDS.each do |f|
      next unless r.key?(f)
      v = r[f].to_s.strip
      @run[f] = v.empty? ? nil : v.to_i
    end
    { "actual_start_time" => "start", "actual_end_time" => "end" }.each do |f, key|
      next unless r.key?(key)
      t = at(r[key])
      next errors << "Run #{key}: \"#{r[key]}\" isn't a time" if t == :bad
      @run[f] = t
    end
    if @run.start_odometer && @run.end_odometer && @run.end_odometer < @run.start_odometer
      errors << "End odometer #{@run.end_odometer} is less than the start #{@run.start_odometer}"
    end
    if @run.actual_start_time && @run.actual_end_time && @run.actual_end_time < @run.actual_start_time
      errors << "The run ends before it starts"
    end
    if @run.will_save_change_to_vehicle_id? && @run.vehicle
      @run.valid?
      errors.concat(@run.errors.full_messages_for(:vehicle_id))
    end
  end

  def apply_stops
    @dirty_stops = []
    rows = @form[:stops] || {}
    stops.each do |s|
      row = rows[s.id.to_s] or next
      arrived = at(row[:arrived])
      done = at(row[:done])
      label = stop_label(s)
      next errors << "#{label}: \"#{row[:arrived]}\" isn't a time" if arrived == :bad
      next errors << "#{label}: \"#{row[:done]}\" isn't a time" if done == :bad
      arrived ||= done if done   # a single time: arrived and done then
      errors << "#{label}: done at #{fmt(done)}, before arriving at #{fmt(arrived)}" if arrived && done && done < arrived
      next if same?(s.arrival_time, arrived) && same?(s.finish_time, done)
      s.arrival_time = arrived
      s.finish_time = done
      s.status_code = done ? Itinerary::STATUS_COMPLETED : (arrived ? Itinerary::STATUS_IN_PROGRESS : Itinerary::STATUS_PENDING)
      s.times_typed_by = @user.username
      s.times_typed_at = Time.current
      @dirty_stops << s
    end
    @changed_stops = @dirty_stops.size
  end

  def apply_results
    @dirty_trips = []
    results = @form[:results] || {}
    stops.map(&:trip).compact.uniq.each do |trip|
      next unless results.key?(trip.id.to_s)
      code = results[trip.id.to_s].to_s
      new_result = code.empty? ? nil : TripResult.find_by(code: code)
      next errors << "#{trip.customer&.name}: no trip result \"#{code}\"" if code.present? && new_result.nil?
      next if new_result&.id == trip.trip_result_id
      trip.trip_result = new_result
      # a no-show is judged against the window by the arrival typed here
      if new_result&.code == "NS"
        pickup = stops.find { |s| s.trip_id == trip.id && s.leg_flag == 1 }
        reason = PickupWindow.for(trip)&.no_show_refusal(at: [Time.current, pickup&.finish_time].compact.min, arrived_at: pickup&.arrival_time)
        next errors << "#{trip.customer&.name}: #{reason}" if reason
        if pickup && pickup.finish_time
          pickup.status_code = Itinerary::STATUS_OTHER
          @dirty_stops << pickup unless @dirty_stops.include?(pickup)
        end
      end
      @dirty_trips << trip
    end
  end

  # A drop-off can't be done before its pick-up; stops can't be outside the run.
  def check_order
    stops.group_by(&:trip_id).each do |trip_id, legs|
      next unless trip_id
      up = legs.find { |s| s.leg_flag == 1 }
      down = legs.find { |s| s.leg_flag == 2 }
      if up&.finish_time && down&.finish_time && down.finish_time < up.finish_time
        errors << "#{stop_label(down)}: dropped off at #{fmt(down.finish_time)}, before the pick-up at #{fmt(up.finish_time)}"
      end
    end
    times = stops.flat_map { |s| [s.arrival_time, s.finish_time] }.compact
    if times.any? && @run.actual_start_time && times.min < @run.actual_start_time
      errors << "A stop at #{fmt(times.min)} is before the run's start at #{fmt(@run.actual_start_time)}"
    end
    if times.any? && @run.actual_end_time && times.max > @run.actual_end_time
      errors << "A stop at #{fmt(times.max)} is after the run's end at #{fmt(@run.actual_end_time)}"
    end
  end

  def stop_label(s)
    kind = { 0 => "Start of run", 1 => "pick-up", 2 => "drop-off", 3 => "End of run" }[s.leg_flag] || "stop"
    s.trip ? "#{s.trip.customer&.name} #{kind}" : kind
  end

  def same?(a, b)
    (a.nil? && b.nil?) || (a && b && a.to_i / 60 == b.to_i / 60)
  end

  def fmt(t)
    t&.in_time_zone&.strftime("%-l:%M %p")
  end
end
