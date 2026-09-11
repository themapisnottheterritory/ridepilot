# NTD Report
# Modify an existing blank template
#
# One workbook per service mode (NTD reports demand response and fixed route
# as separate modes):
#   demand_response — the original path: runs + trips + run_distances.
#   fixed_route     — runs + walk-on boardings: miles from the odometer,
#                     hours from the clock, unlinked passenger trips from
#                     boarded counts, passenger miles left blank (decision D4
#                     in ops/fixed-route-phase1-plan.md).

class NtdReport

  TEMPLATE_PATH = "#{Rails.root}/public/ntd_template.xlsx"
  MODES = Run::SERVICE_MODES

  attr_reader :workbook, :mode

  def initialize(provider, year, month, mode: 'demand_response')
    @provider = provider
    @year = year
    @month = month
    @mode = MODES.include?(mode.to_s) ? mode.to_s : 'demand_response'
    @start_date = Date.new(year, 1, 1)
    @end_date = Date.new(year, month, 1).at_end_of_month + 1.day
  end

  def fixed_route?
    @mode == 'fixed_route'
  end

  def export!
    @workbook = RubyXL::Parser.parse(TEMPLATE_PATH)
    @worksheet = @workbook[0] #first worksheet

    get_base_data

    process_periods_of_service
    process_year_month_headers
    if fixed_route?
      process_fixed_route_operations
      process_fixed_route_miles_and_hours
    else
      process_operations
      process_miles_and_hours
    end

    @workbook.calc_pr.full_calc_on_load = true
    @workbook
  end

  def get_base_data
    @runs = Run.complete.for_provider(@provider.try(:id)).for_date_range(@start_date, @end_date).where(service_mode: @mode)
    @weekday_runs = @runs.where("extract(dow from date) in (?)", (1..5).to_a)
    @sat_runs = @runs.where("extract(dow from date) = ?", 6)
    @sun_runs = @runs.where("extract(dow from date) = ?", 0)

    if fixed_route?
      @boardings = FixedRouteBoarding.joins(:run).where(provider_id: @provider.try(:id))
        .where(runs: { complete: true, service_mode: 'fixed_route' })
        .where("runs.date >= ? and runs.date < ?", @start_date, @end_date)
      @weekday_boardings = @boardings.where("extract(dow from runs.date) in (?)", (1..5).to_a)
      @sat_boardings = @boardings.where("extract(dow from runs.date) = ?", 6)
      @sun_boardings = @boardings.where("extract(dow from runs.date) = ?", 0)
    else
      @trips = Trip.for_provider(@provider.try(:id)).completed.joins(:run, :funding_source)
        .where("runs.complete = ?", true).where(runs: { service_mode: 'demand_response' })
        .for_date_range(@start_date, @end_date)
        .where(funding_sources: {ntd_reportable: true})
      @weekday_trips = @trips.where("extract(dow from pickup_time) in (?)", (1..5).to_a)
      @sat_trips = @trips.where("extract(dow from pickup_time) = ?", 6)
      @sun_trips = @trips.where("extract(dow from pickup_time) = ?", 0)
    end
  end

  def process_periods_of_service
    @weekday_earliest_runs = @weekday_runs.where.not(scheduled_start_time_string: nil).group(:date).minimum(:scheduled_start_time_string)
    @worksheet[1][3].change_contents (get_average_time(@weekday_earliest_runs))
    @sat_earliest_runs = @sat_runs.where.not(scheduled_start_time_string: nil).group(:date).minimum(:scheduled_start_time_string)
    @worksheet[1][4].change_contents (get_average_time(@sat_earliest_runs))
    @sun_earliest_runs = @sun_runs.where.not(scheduled_start_time_string: nil).group(:date).minimum(:scheduled_start_time_string)
    @worksheet[1][5].change_contents (get_average_time(@sun_earliest_runs))

    @weekday_latest_runs = @weekday_runs.where.not(scheduled_end_time_string: nil).group(:date).maximum(:scheduled_end_time_string)
    @worksheet[2][3].change_contents (get_average_time(@weekday_latest_runs))
    @sat_latest_runs = @sat_runs.where.not(scheduled_end_time_string: nil).group(:date).maximum(:scheduled_end_time_string)
    @worksheet[2][4].change_contents (get_average_time(@sat_latest_runs))
    @sun_latest_runs = @sun_runs.where.not(scheduled_end_time_string: nil).group(:date).maximum(:scheduled_end_time_string)
    @worksheet[2][5].change_contents (get_average_time(@sun_latest_runs))
  end

  def process_year_month_headers
    # year
    @worksheet[4][3].change_contents @year
    # month
    (1..12).each do |m|
      @worksheet[4][m + 4].change_contents Date.new(@year, m, 1)
    end
  end

  # ---- demand response (unchanged) -------------------------------------------

  def process_operations
    @num_max_operated_vehicles = @trips.group("extract(month from runs.date)").count("distinct(runs.vehicle_id)")

    @num_unlinked_passenger_weekday_trips = sum_monthly_trip_size @weekday_trips
    @num_unlinked_passenger_sat_trips = sum_monthly_trip_size @sat_trips
    @num_unlinked_passenger_sun_trips = sum_monthly_trip_size @sun_trips

    @days_operated_weekday = count_monthly_days_operated @weekday_trips
    @days_operated_sat = count_monthly_days_operated @sat_trips
    @days_operated_sun = count_monthly_days_operated @sun_trips

    write_operations
  end

  def process_miles_and_hours
    @weekday_stats = monthly_miles_hours @weekday_trips
    @sat_stats = monthly_miles_hours @sat_trips
    @sun_stats = monthly_miles_hours @sun_trips

    write_miles_and_hours
  end

  # ---- fixed route -----------------------------------------------------------

  def process_fixed_route_operations
    @num_max_operated_vehicles = @runs.group("extract(month from runs.date)").count("distinct(runs.vehicle_id)")

    @num_unlinked_passenger_weekday_trips = sum_monthly_boardings @weekday_boardings
    @num_unlinked_passenger_sat_trips = sum_monthly_boardings @sat_boardings
    @num_unlinked_passenger_sun_trips = sum_monthly_boardings @sun_boardings

    @days_operated_weekday = count_monthly_run_days @weekday_runs
    @days_operated_sat = count_monthly_run_days @sat_runs
    @days_operated_sun = count_monthly_run_days @sun_runs

    write_operations
  end

  def process_fixed_route_miles_and_hours
    @weekday_stats = monthly_fixed_miles_hours @weekday_runs
    @sat_stats = monthly_fixed_miles_hours @sat_runs
    @sun_stats = monthly_fixed_miles_hours @sun_runs

    write_miles_and_hours
  end

  # ---- shared cell writers ---------------------------------------------------

  def write_operations
    (1..12).each do |m|
      # Vehicles operated in maximum service
      max_vehicles = @num_max_operated_vehicles[m.to_f]
      @worksheet[6][m + 4].change_value(max_vehicles) unless max_vehicles.nil?

      # Vehicles available in maximum service
      monthly_tracking = VehicleMonthlyTracking.where(provider_id: @provider.try(:id), year: @year, month: m).first
      @worksheet[7][m + 4].change_value(monthly_tracking.max_available_count) unless monthly_tracking.nil?

      # Unlinked passenger trips
      weekday_trip_size = @num_unlinked_passenger_weekday_trips[m.to_f]
      @worksheet[10][m + 4].change_value(weekday_trip_size) unless weekday_trip_size.nil?
      sat_trip_size = @num_unlinked_passenger_sat_trips[m.to_f]
      @worksheet[11][m + 4].change_value(sat_trip_size) unless sat_trip_size.nil?
      sun_trip_size = @num_unlinked_passenger_sun_trips[m.to_f]
      @worksheet[12][m + 4].change_value(sun_trip_size) unless sun_trip_size.nil?

      # # of days operated
      weekday_days = @days_operated_weekday[m.to_f]
      @worksheet[16][m + 4].change_value(weekday_days) unless weekday_days.nil?
      sat_days = @days_operated_sat[m.to_f]
      @worksheet[17][m + 4].change_value(sat_days) unless sat_days.nil?
      sun_days = @days_operated_sun[m.to_f]
      @worksheet[18][m + 4].change_value(sun_days) unless sun_days.nil?
    end
  end

  def write_miles_and_hours
    @total_miles_weekday = @weekday_stats[:total_miles]
    @total_miles_sat = @sat_stats[:total_miles]
    @total_miles_sun = @sun_stats[:total_miles]

    @revenue_miles_weekday = @weekday_stats[:revenue_miles]
    @revenue_miles_sat = @sat_stats[:revenue_miles]
    @revenue_miles_sun = @sun_stats[:revenue_miles]

    @passenger_miles_weekday = @weekday_stats[:passenger_miles]
    @passenger_miles_sat = @sat_stats[:passenger_miles]
    @passenger_miles_sun = @sun_stats[:passenger_miles]

    @total_hours_weekday = @weekday_stats[:total_hours]
    @total_hours_sat = @sat_stats[:total_hours]
    @total_hours_sun = @sun_stats[:total_hours]

    @total_revenue_hours_weekday = @weekday_stats[:total_revenue_hours]
    @total_revenue_hours_sat = @sat_stats[:total_revenue_hours]
    @total_revenue_hours_sun = @sun_stats[:total_revenue_hours]

    (1..12).each do |m|
      # Total Actual Miles
      total_miles_weekday = @total_miles_weekday[m.to_f]
      @worksheet[23][m + 4].change_value(total_miles_weekday) unless total_miles_weekday.nil?
      total_miles_sat = @total_miles_sat[m.to_f]
      @worksheet[24][m + 4].change_value(total_miles_sat) unless total_miles_sat.nil?
      total_miles_sun = @total_miles_sun[m.to_f]
      @worksheet[25][m + 4].change_value(total_miles_sun) unless total_miles_sun.nil?

      # Total Vehicle Revenue Miles
      revenue_miles_weekday = @revenue_miles_weekday[m.to_f]
      @worksheet[28][m + 4].change_value(revenue_miles_weekday) unless revenue_miles_weekday.nil?
      revenue_miles_sat = @revenue_miles_sat[m.to_f]
      @worksheet[29][m + 4].change_value(revenue_miles_sat) unless revenue_miles_sat.nil?
      revenue_miles_sun = @revenue_miles_sun[m.to_f]
      @worksheet[30][m + 4].change_value(revenue_miles_sun) unless revenue_miles_sun.nil?

      # Scheduled Revenue Miles: save as Total Vehicle Revenue Miles
      @worksheet[38][m + 4].change_value(revenue_miles_weekday) unless revenue_miles_weekday.nil?
      @worksheet[39][m + 4].change_value(revenue_miles_sat) unless revenue_miles_sat.nil?
      @worksheet[40][m + 4].change_value(revenue_miles_sun) unless revenue_miles_sun.nil?

      # Passenger Miles (Ops Research) — left blank on the fixed-route workbook
      passenger_miles_weekday = @passenger_miles_weekday[m.to_f]
      @worksheet[43][m + 4].change_value(passenger_miles_weekday) unless passenger_miles_weekday.nil?
      passenger_miles_sat = @passenger_miles_sat[m.to_f]
      @worksheet[44][m + 4].change_value(passenger_miles_sat) unless passenger_miles_sat.nil?
      passenger_miles_sun = @passenger_miles_sun[m.to_f]
      @worksheet[45][m + 4].change_value(passenger_miles_sun) unless passenger_miles_sun.nil?

      # Total Actual Hours
      total_hours_weekday = @total_hours_weekday[m.to_f]
      @worksheet[49][m + 4].change_value(total_hours_weekday) unless total_hours_weekday.nil?
      total_hours_sat = @total_hours_sat[m.to_f]
      @worksheet[50][m + 4].change_value(total_hours_sat) unless total_hours_sat.nil?
      total_hours_sun = @total_hours_sun[m.to_f]
      @worksheet[51][m + 4].change_value(total_hours_sun) unless total_hours_sun.nil?

      # Total Revenue Hours
      total_revenue_hours_weekday = @total_revenue_hours_weekday[m.to_f]
      @worksheet[54][m + 4].change_value(total_revenue_hours_weekday) unless total_revenue_hours_weekday.nil?
      total_revenue_hours_sat = @total_revenue_hours_sat[m.to_f]
      @worksheet[55][m + 4].change_value(total_revenue_hours_sat) unless total_revenue_hours_sat.nil?
      total_revenue_hours_sun = @total_revenue_hours_sun[m.to_f]
      @worksheet[56][m + 4].change_value(total_revenue_hours_sun) unless total_revenue_hours_sun.nil?

    end
  end


  private

  def get_average_time(times_by_date)
    day_count = times_by_date.count
    if day_count == 0
      'N/A'
    else
      total_hours = total_mins = 0
      times_by_date.each do |date, time_str|
        time_parts = time_str.split(":")
        total_hours += time_parts[0].to_i
        total_mins += time_parts[1].to_i
      end

      sum_mins = total_hours * 60 + total_mins
      average_mins = sum_mins / day_count
      hour = average_mins / 60
      min = average_mins - hour * 60
      DateTime.new(@year, 1, 1, hour, min)
    end
  end

  def sum_monthly_trip_size(trips)
    trips.group("extract(month from pickup_time)").sum("customer_space_count + guest_count + attendant_count")
  end

  def count_monthly_days_operated(trips)
    trips.group("extract(month from runs.date)").count("distinct(runs.date)")
  end

  def monthly_miles_hours(trips)
    run_ids = trips.pluck(:run_id).uniq
    runs_rel = Run.where(id: run_ids).joins(:run_distance).group("extract(month from runs.date)")
    {
      total_miles: runs_rel.sum("run_distances.ntd_total_miles"),
      revenue_miles: runs_rel.sum("run_distances.ntd_total_revenue_miles"),
      passenger_miles: runs_rel.sum("run_distances.ntd_total_passenger_miles"),
      total_hours: runs_rel.sum("run_distances.ntd_total_hours"),
      total_revenue_hours: runs_rel.sum("run_distances.ntd_total_revenue_hours"),
    }
  end

  # ---- fixed-route helpers (keys are month Floats, like extract(month) gives) --

  # Unlinked passenger trips = riders who boarded.
  def sum_monthly_boardings(boardings)
    boardings.group("extract(month from runs.date)").sum(:boarded_count)
  end

  def count_monthly_run_days(runs)
    runs.group("extract(month from runs.date)").count("distinct(runs.date)")
  end

  # Miles from the odometer (revenue service starts and ends at the depot,
  # decision D3, so revenue miles = total miles); hours from the clock, actual
  # when the driver started and ended the run, scheduled otherwise; revenue
  # hours = hours minus the unpaid break. Passenger miles are not computable
  # from boardings alone (D4) and stay blank.
  def monthly_fixed_miles_hours(runs)
    stats = { total_miles: Hash.new(0), revenue_miles: Hash.new(0), passenger_miles: {}, total_hours: Hash.new(0.0), total_revenue_hours: Hash.new(0.0) }
    runs.each do |run|
      m = run.date.month.to_f
      if run.start_odometer && run.end_odometer && run.end_odometer > run.start_odometer
        miles = run.end_odometer - run.start_odometer
        stats[:total_miles][m] += miles
        stats[:revenue_miles][m] += miles
      end
      hours = run.duration_in_hours.to_f
      stats[:total_hours][m] += hours
      stats[:total_revenue_hours][m] += [hours - run.unpaid_driver_break_time.to_i / 60.0, 0].max
    end
    stats.each_value { |h| h.default = nil if h.is_a?(Hash) }
    stats
  end
end
