# Does a bus's garage fit where it runs? (Philz, 2026-10-06.) A run starts and
# ends at its own start/end, or its bus's garage (Run#from_garage_address).
# When that is the wrong yard, the route optimizer, the tablet's times and the
# Vehicle Summary's non-revenue miles all start the bus somewhere it isn't:
# bus R9 on the Matagorda runs, garaged on file in Victoria, drove "136 miles
# of garage legs" on a 54-mile run; bus 1785 ran RGON2 in Gonzales every day
# from a Victoria garage 55 miles away.
#
# One place for the rule, used by the nightly address check (AddressScan), the
# bus's page (vehicles/_garage_panel) and the Vehicle Summary report:
#   GarageFit.garages(run)     -> [start, end] the run uses
#   GarageFit.legs_fit?(legs, odometer_miles)
#   GarageFit.buses            -> active buses whose runs start far from their
#                                 garage (median first stop over FAR_MILES)
#   GarageFit.for_vehicle(bus) -> that, for one bus, or nil
#   GarageFit.runs             -> runs whose own start (set on the run, not
#                                 the bus's garage) is far from their first stop
# Runs looked at: DAYS_BACK days ago to DAYS_AHEAD from now. Distances are as
# the crow flies (no lookups); a yard is 25+ miles off, not a few.
module GarageFit
  FAR_MILES = 25
  # Garage legs this large a share of the odometer mean the garage on file is
  # not where the bus started (Vehicle Summary)
  MAX_GARAGE_SHARE = 0.75
  DAYS_BACK = 30
  DAYS_AHEAD = 14
  SAME_PLACE_MILES = 0.1   # a run's own copy of its bus's garage

  Bus = Struct.new(:vehicle, :garage, :runs, :median_miles, :town, keyword_init: true)
  RunMisfit = Struct.new(:run, :start, :first_stop, :miles, keyword_init: true)

  module_function

  def garages(run)
    garage = run.vehicle&.garage_address
    [run.from_garage_address || garage, run.to_garage_address || garage]
  end

  def legs_fit?(legs, odometer_miles)
    legs <= MAX_GARAGE_SHARE * odometer_miles
  end

  def buses(vehicles = Vehicle.where(active: true))
    runs = window_runs.where(vehicle_id: vehicles.select(:id)).to_a
    firsts = first_stops(runs)
    vehicles.includes(:garage_address).filter_map do |v|
      stops = runs.select { |r| r.vehicle_id == v.id }.filter_map { |r| firsts[r.id] }
      next if stops.empty?
      g = v.garage_address
      town = stops.map { |a| a.city.to_s.strip.titleize }.reject(&:blank?).tally.max_by(&:last)&.first
      unless g&.latitude
        next Bus.new(vehicle: v, garage: g, runs: stops.size, median_miles: nil, town: town)
      end
      miles = stops.map { |a| miles(g, a) }.sort
      median = miles[miles.size / 2]
      Bus.new(vehicle: v, garage: g, runs: stops.size, median_miles: median, town: town) if median > FAR_MILES
    end
  end

  def for_vehicle(vehicle)
    buses(Vehicle.where(id: vehicle.id)).first
  end

  def runs
    list = window_runs.where.not(from_garage_address_id: nil).includes(:from_garage_address, vehicle: :garage_address).to_a
    firsts = first_stops(list)
    list.filter_map do |r|
      start, first = r.from_garage_address, firsts[r.id]
      next unless start&.latitude && first
      bus = r.vehicle&.garage_address
      next if bus&.latitude && (start.id == bus.id || miles(start, bus) <= SAME_PLACE_MILES)   # follows its bus
      m = miles(start, first)
      RunMisfit.new(run: r, start: start, first_stop: first, miles: m) if m > FAR_MILES
    end
  end

  def window_runs
    Run.where(date: (Time.zone.today - DAYS_BACK)..(Time.zone.today + DAYS_AHEAD)).where.not(vehicle_id: nil)
  end

  # run id => the pick-up address of its first trip (pinned)
  def first_stops(runs)
    ids = runs.map(&:id)
    return {} if ids.empty?
    pairs = Trip.where(run_id: ids).where.not(pickup_address_id: nil)
                .select("DISTINCT ON (trips.run_id) trips.run_id, trips.pickup_address_id")
                .order(Arel.sql("trips.run_id, trips.pickup_time")).map { |t| [t.run_id, t.pickup_address_id] }
    addresses = Address.where(id: pairs.map(&:last)).index_by(&:id)
    pairs.to_h { |run_id, aid| [run_id, addresses[aid]] }.select { |_, a| a&.latitude }
  end

  def miles(a, b)
    TownCentres.miles({ lat: a.latitude, lon: a.longitude }, b.latitude, b.longitude)
  end
end
