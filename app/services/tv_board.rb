# Numbers for the dispatch TV (/tv, TvController): today's service at one
# agency, as JSON the board polls. Counts, run names and drivers only -- a
# wall in the office never shows riders' names or addresses.
#
#   hero       trips without a run: today's count, tone and the next pickups
#   on_road    runs that have started and not ended
#   days       today and the next two days: booked, without a run, runs with
#              trips but no driver / no bus
#   strip      trips today, rides completed, no-shows and cancellations,
#              fixed-route boardings
class TvBoard
  CANCELLED = %w[CANC LTCANC SDCANC].freeze
  SOON = 2.hours   # a trip without a run this close to pickup turns the board red

  def initialize(provider)
    @provider = provider
    @now = Time.zone.now
    @today = @now.to_date
  end

  def as_json(*)
    {
      provider: @provider.name,
      updated_at: @now.iso8601,
      hero: hero,
      on_road: on_road,
      days: (0..2).map { |i| day_summary(@today + i) },
      strip: strip,
      quote: FooterNote.quote(@today)
    }
  end

  private

  def trips_on(day)
    Trip.where(provider_id: @provider.id, pickup_time: day.in_time_zone.all_day)
  end

  # booked and still expected to happen: not cancelled, no-showed or turned down
  def live_trips_on(day)
    trips_on(day).left_joins(:trip_result).where("trip_results.id IS NULL OR trip_results.code NOT IN (?)", CANCELLED + %w[NS TD UNMET MT])
  end

  def without_run(day)
    live_trips_on(day).where(run_id: nil).where("trips.cab IS NOT TRUE").where("trips.is_stand_by IS NOT TRUE")
  end

  def hero
    today_open = without_run(@today)
    count = today_open.count
    upcoming = today_open.where("trips.pickup_time >= ?", @now - 30.minutes).order(:pickup_time).limit(8).pluck(:pickup_time)
    soon = today_open.where("trips.pickup_time BETWEEN ? AND ?", @now - 30.minutes, @now + SOON).count
    tomorrow = without_run(@today + 1).count
    tone, text =
      if soon > 0 then ["crit", "#{soon} #{soon == 1 ? 'pickup' : 'pickups'} within 2 hours #{soon == 1 ? 'needs' : 'need'} a run"]
      elsif count > 0 then ["warn", "Today's trips still need runs"]
      elsif tomorrow > 0 then ["warn", "Today is covered · tomorrow needs runs"]
      else ["good", "Every trip has a run"]
      end
    { count: count, tomorrow: tomorrow, tone: tone, text: text,
      next_pickups: upcoming.map { |t| { at: t.in_time_zone.strftime("%-l:%M %P"), soon: t <= @now + SOON } } }
  end

  def on_road
    runs = Run.not_cancelled.where(provider_id: @provider.id, date: @today)
              .where.not(actual_start_time: nil).where(actual_end_time: nil)
              .includes(:driver, :vehicle).order(:actual_start_time).to_a
    runs.first(8).map do |run|
      fixed = run.fixed_route?
      done, total = fixed ? [boardings(run_id: run.id), nil] : trip_progress(run)
      { name: run.name, driver: run.driver&.user_name, vehicle: run.vehicle&.name, fixed: fixed,
        since: run.actual_start_time.in_time_zone.strftime("%-l:%M %p"), done: done, total: total }
    end + (runs.size > 8 ? [{ more: runs.size - 8 }] : [])
  end

  def trip_progress(run)
    trips = run.trips.to_a
    [trips.count { |t| t.trip_result&.code.present? }, trips.size]
  end

  def day_summary(day)
    runs_with_trips = Run.not_cancelled.where(provider_id: @provider.id, date: day)
                         .where(id: live_trips_on(day).where.not(run_id: nil).select(:run_id))
    {
      label: day == @today ? "Today" : (day == @today + 1 ? "Tomorrow" : day.strftime("%A")),
      date: day.strftime("%a %-m/%-d"),
      booked: live_trips_on(day).count,
      without_run: without_run(day).count,
      no_driver: runs_with_trips.where(driver_id: nil).count,
      no_bus: runs_with_trips.where(vehicle_id: nil).count
    }
  end

  def strip
    by_code = trips_on(@today).left_joins(:trip_result).group("trip_results.code").count
    {
      trips: by_code.values.sum,
      completed: FooterNote.rides_completed(@provider, @today),
      no_shows: by_code["NS"].to_i,
      cancelled: CANCELLED.sum { |c| by_code[c].to_i },
      boardings: boardings(recorded_at: @today.in_time_zone.all_day)
    }
  end

  def boardings(conditions)
    FixedRouteBoarding.where(provider_id: @provider.id).where(conditions).sum(:boarded_count)
  end
end
