# Training / demo server tasks.
#
#   rake training:scrub   — replace every rider with a fictitious one, drop chat,
#                           GPS, paper trail and action logs. Street addresses are
#                           kept so maps, distances and ETAs still work.
#   rake training:seed    — trainee driver accounts + today's runs (3 trips each),
#                           one run with a prior DVIR defect for the prior-defect
#                           screen, and (once fixed route lands) fixed-route runs.
#   rake training:reset   — scrub then seed. ops/training/training-reset.sh runs
#                           this nightly on the training box after the restore.
#   rake training:status  — what the training box currently holds.
#
# GUARD: these tasks destroy data. They refuse to run unless TRAINING_MODE=true
# is set in the environment (config/application.yml on the training box), so a
# stray `rake training:reset` on the production box does nothing.
namespace :training do
  FIRST_NAMES = %w[Ada Bea Cal Dora Eli Fay Gus Hana Ivy Jed Kim Lou Mae Ned Ola Pat Quin Rae Sal Tia
                   Uma Vic Wes Xia Yul Zed Ana Bo Cy Dee Eve Flo Gil Hal Ida Jo Kai Lee Moe Nia].freeze
  LAST_NAMES  = %w[Abbott Bishop Cantu Dorsey Ennis Farley Guerra Hobbs Ingram Juarez Keller Lozano
                   Mendez Nunez Ortega Pruitt Quiroz Rangel Salas Torres Ulrich Varela Whitley Ybarra
                   Zapata Acosta Baird Cobb Dunn Eaton Flores Gomez Hicks Irwin Joyce Kemp Lara Mora Nash Oakes].freeze
  DEFAULT_PASSWORD = "Train-2026!".freeze
  RUN_PREFIX = "Training Run".freeze

  def training_guard!
    return if ENV["TRAINING_MODE"].to_s == "true"
    abort "Refusing: TRAINING_MODE is not 'true' in this environment. These tasks destroy rider data " \
          "and only run on the training box (config/application.yml: TRAINING_MODE: 'true')."
  end

  def sql(statement)
    ActiveRecord::Base.connection.execute(statement)
  end

  def pg_array(list)
    "ARRAY[" + list.map { |s| "'#{s}'" }.join(",") + "]"
  end

  desc "Replace every rider with a fictitious one and drop chat/GPS/paper-trail/action logs"
  task scrub: :environment do
    training_guard!
    t0 = Time.now
    ActiveRecord::Base.transaction do
      # Riders: deterministic fake names from the id, so a customer keeps the
      # same fake name across nightly resets and trainers can refer to them.
      sql <<~SQL
        UPDATE customers SET
          first_name = (#{pg_array(FIRST_NAMES)})[(id % #{FIRST_NAMES.size}) + 1],
          last_name  = (#{pg_array(LAST_NAMES)})[((id / #{FIRST_NAMES.size}) % #{LAST_NAMES.size}) + 1],
          middle_initial = chr(65 + ((id / #{FIRST_NAMES.size * LAST_NAMES.size}) % 26)),
          phone_number_1 = '555-01' || lpad((id % 100)::text, 2, '0'),
          phone_number_2 = NULL,
          email = NULL,
          birth_date = CASE WHEN birth_date IS NULL THEN NULL ELSE DATE '1940-01-01' + ((id * 37) % 20000) END,
          private_notes = NULL, mobility_notes = NULL, emergency_contact_notes = NULL, comments = NULL,
          message = NULL, inactivated_reason = NULL, active_status_changed_reason = NULL, ada_ineligible_reason = NULL,
          public_notes = 'TRAINING DATA - fictitious rider',
          prime_number = NULL,
          code = 'T' || id::text,
          sms_notifications_enabled = false
      SQL
      # Rider addresses: keep the street (maps/ETA/distance need it), drop the label,
      # phone and notes that can carry a name.
      sql "UPDATE addresses SET name = NULL, building_name = NULL, phone_number = NULL, notes = NULL WHERE type = 'CustomerCommonAddress'"
      # Staff and driver home addresses: move everyone to the depot.
      depot = sql("SELECT the_geom FROM addresses WHERE type = 'GarageAddress' AND deleted_at IS NULL LIMIT 1").first
      geom_sql = depot ? "'#{depot['the_geom']}'" : "the_geom"
      sql "UPDATE addresses SET name = NULL, building_name = NULL, address = '1908 North Laurent Street', city = 'Victoria', state = 'TX', zip = '77901', phone_number = NULL, notes = NULL, the_geom = #{geom_sql} WHERE type IN ('DriverAddress','UserAddress')"
      sql "UPDATE emergency_contacts SET name = 'Emergency Contact', phone_number = '555-0100', relationship = NULL"
      sql "UPDATE trips SET notes = NULL, pickup_address_notes = NULL, dropoff_address_notes = NULL"
      sql "UPDATE users SET reset_password_token = NULL, reset_password_sent_at = NULL, current_sign_in_ip = NULL, last_sign_in_ip = NULL"
      sql "DELETE FROM messages"
      sql "DELETE FROM document_associations"
      sql "DELETE FROM documents"
      sql "TRUNCATE versions"
      sql "TRUNCATE activities"
      sql "TRUNCATE gps_locations CASCADE" rescue sql("DELETE FROM gps_locations")
    end
    puts "scrubbed #{Customer.unscoped.count} riders in #{(Time.now - t0).round}s"
  end

  desc "Trainee drivers + today's runs with trips, and a run with a prior DVIR defect"
  task :seed, [:trainees] => :environment do |_t, args|
    training_guard!
    provider  = Provider.find(1)
    count     = (args[:trainees] || ENV["TRAINEES"] || 6).to_i
    password  = ENV["TRAINING_PASSWORD"].presence || DEFAULT_PASSWORD
    today     = Date.today
    tz        = Time.zone

    depot = GarageAddress.where(provider_id: provider.id).first ||
            GarageAddress.create!(provider_id: provider.id, name: "Transit Depot", address: "1908 North Laurent Street",
                                  city: "Victoria", state: "TX", zip: "77901", the_geom: Address.compute_geom(28.8140, -96.9836))
    destinations = ["%walmart%navarro%", "%medical center%", "%library%"].map { |pat|
      ProviderCommonAddress.where(provider_id: provider.id).where("name ILIKE ?", pat).where.not(the_geom: nil).first
    }.compact
    destinations = ProviderCommonAddress.where(provider_id: provider.id).where.not(the_geom: nil).limit(3).to_a if destinations.empty?
    abort "no geocoded provider common addresses to use as destinations" if destinations.empty?

    riders = Customer.where(provider_id: provider.id, active: true).joins(:address)
                     .where(addresses: { in_district: true }).where.not(addresses: { the_geom: nil })
    abort "no usable riders (active, geocoded, in district)" if riders.count == 0
    ambulatory = Mobility.find_by(name: "Ambulatory") || Mobility.first
    funding    = FundingSource.find(2) rescue FundingSource.first
    purpose    = TripPurpose.find_by(name: "Medical") || TripPurpose.first
    # Wipe earlier training runs (and their trips, reports, maintenance events)
    # so the seed is idempotent and a re-run today gives the same vehicles.
    Run.unscoped.where("name LIKE ?", "#{RUN_PREFIX}%").where(date: (today - 7)..(today + 1)).find_each do |old|
      Trip.unscoped.where(run_id: old.id).each { |tr| tr.really_destroy! rescue tr.delete }
      VehicleInspectionReport.where(run_id: old.id).each { |r| r.run_vehicle_inspections.delete_all; r.delete }
      old.really_destroy! rescue old.delete
    end
    VehicleMaintenanceEvent.where("services_performed LIKE 'DVIR % defect%' AND created_at > ?", today - 8).delete_all
    fixed_routes = %w[Red Gold].map { |nm| FixedRoute.for_provider(provider.id).active.find_by(name: nm) }.compact
    fixed_routes = FixedRoute.for_provider(provider.id).active.where(kind: "city").default_order.first(2) if fixed_routes.empty?
    FixedRouteBoarding.with_deleted.joins(:run).where(runs: { name: Run.unscoped.where("name LIKE ?", "#{RUN_PREFIX}%").select(:name) }).each(&:really_destroy!) rescue nil
    used_vehicle_ids = Run.where(date: today).where.not(vehicle_id: nil).pluck(:vehicle_id)
    vehicles = Vehicle.for_provider(provider.id).where(active: true).where.not(id: used_vehicle_ids).default_order.to_a

    accounts = []
    (1..count).each do |n|
      uname = format("trainee%02d", n)
      user = User.with_deleted.find_by(username: uname) rescue User.find_by(username: uname)
      user ||= User.new(username: uname, email: "#{uname}@training.gcrpc.org",
                        first_name: "Trainee", last_name: format("%02d", n))
      user.deleted_at = nil if user.respond_to?(:deleted_at)
      user.password = password; user.password_confirmation = password
      user.current_provider = provider
      user.save!(validate: false)
      Role.where(provider: provider, user: user).first || Role.create!(provider: provider, user: user, level: Role::USER_LEVEL)
      user.ensure_authentication_token if user.respond_to?(:ensure_authentication_token) && user.authentication_token.blank?
      user.save!(validate: false) if user.changed?

      driver = Driver.with_deleted.find_by(user_id: user.id) rescue Driver.find_by(user_id: user.id)
      unless driver
        addr = DriverAddress.create!(provider_id: provider.id, address: depot.address, city: depot.city, state: depot.state,
                                     zip: depot.zip, the_geom: depot.the_geom, is_driver_associated: true)
        driver = Driver.new(user: user, provider: provider, address: addr, name: "Trainee #{format('%02d', n)}", email: user.email)
      end
      driver.deleted_at = nil if driver.respond_to?(:deleted_at)
      driver.active = true; driver.paid = true if driver.respond_to?(:paid=)
      driver.save!(validate: false)

      vehicle = vehicles.shift or abort("ran out of unassigned active vehicles at trainee #{n}")
      # The last two trainees drive fixed routes (Red, then Gold) so a class
      # covers both service modes; the rest are paratransit.
      fixed_route = fixed_routes.any? && n > count - [2, count].min && n > 0 ? fixed_routes[(count - n) % fixed_routes.size] : nil
      if fixed_route
        run = build_training_run(provider, driver, vehicle, depot, today, "#{RUN_PREFIX} #{format('%02d', n)} #{fixed_route.name}", tz, fixed_route)
        run.public_itineraries.destroy_all
        run.publish_manifest!(false)
        accounts << [uname, password, vehicle.name, run.id, "fixed route #{fixed_route.name}"]
        # Yesterday's completed run on the same route with a dozen walk-ons, so the
        # Fixed Route Ridership report and the NTD fixed-route workbook have a day to show.
        seed_ridership_day(provider, driver, vehicle, depot, today - 1, fixed_route, tz) if n == count
      else
        run = build_training_run(provider, driver, vehicle, depot, today, "#{RUN_PREFIX} #{format('%02d', n)}", tz)
        trips = seed_trips(run, riders, destinations, ambulatory, funding, purpose, tz, today)
        run.public_itineraries.destroy_all
        run.publish_manifest!(false)
        accounts << [uname, password, vehicle.name, run.id, "#{trips.size} trips"]
      end

      # Trainee 01 also has yesterday's run with a defect, so the pre-trip shows
      # a prior unresolved defect (and a maintenance event exists to look at).
      seed_prior_defect(provider, driver, vehicle, depot, today - 1, tz) if n == 1
    end

    puts
    puts "Training accounts (provider #{provider.name}):"
    accounts.each { |u, p, v, r, t| puts format("  %-10s %-14s unit %-6s run #%-5s %s", u, p, v, r, t) }
    puts "Dispatcher/staff logins are the real ones (restored from the backup)."
  end

  desc "Scrub, then seed"
  task reset: :environment do
    training_guard!
    Rake::Task["training:scrub"].invoke
    Rake::Task["training:seed"].invoke
  end

  desc "What the training box currently holds"
  task status: :environment do
    puts "TRAINING_MODE=#{ENV['TRAINING_MODE'].inspect}"
    puts "riders: #{Customer.count}, sample: #{Customer.order(:id).limit(3).map(&:name).join(', ')}"
    puts "trainees: #{User.where('username LIKE ?', 'trainee%').count}"
    puts "training runs today: #{Run.where(date: Date.today).where('name LIKE ?', "#{RUN_PREFIX}%").count}"
    puts "messages: #{Message.count}, versions: #{PaperTrail::Version.count}, gps: #{GpsLocation.count rescue '?'}"
  end

  # ---- helpers -------------------------------------------------------------

  def build_training_run(provider, driver, vehicle, depot, date, name, tz, fixed_route = nil)
    run = Run.new(name: name, date: date, provider: provider, driver: driver, vehicle: vehicle, paid: true,
                  service_mode: (fixed_route ? "fixed_route" : "demand_response"), fixed_route: fixed_route,
                  scheduled_start_time: tz.parse("#{date} #{fixed_route ? '07:30' : '08:00'}"), scheduled_end_time: tz.parse("#{date} 17:00"))
    run.from_garage_address = depot.dup
    run.to_garage_address   = depot.dup
    run.save(validate: false)
    run.send(:add_init_run_itineraries) if run.itineraries.where(trip_id: nil).empty?
    run
  end

  def seed_trips(run, riders, destinations, mobility, funding, purpose, tz, date)
    pickups = %w[08:45 10:30 13:15]
    pool = riders.order(Arel.sql("random()")).limit(pickups.size).to_a
    pool.each_with_index.map do |rider, i|
      pickup_at = tz.parse("#{date} #{pickups[i]}")
      trip = Trip.new(provider: run.provider, customer: rider, run: run,
                      pickup_address: rider.address, dropoff_address: destinations[i % destinations.size],
                      pickup_time: pickup_at, appointment_time: pickup_at + 30.minutes,
                      mobility: rider.mobility || mobility, funding_source: funding, trip_purpose: purpose,
                      customer_space_count: 1, guest_count: 0, attendant_count: 0,
                      direction: :outbound)
      trip.save(validate: false)
      run.add_trip_itineraries!(trip.id)
      trip
    end
  end

  # A finished fixed-route day: twelve walk-ons spread over the route's stops,
  # categories and fare types, odometer and clock filled in, run complete.
  def seed_ridership_day(provider, driver, vehicle, depot, date, route, tz)
    run = build_training_run(provider, driver, vehicle, depot, date, "#{RUN_PREFIX} #{route.name} (yesterday)", tz, route)
    run.update_columns(start_odometer: 61240, end_odometer: 61352, actual_start_time: tz.parse("#{date} 07:31"), actual_end_time: tz.parse("#{date} 16:52"), complete: true)
    stops = route.stops.to_a; cats = RiderCategory.by_provider(provider).default_order.to_a; fares = FareType.by_provider(provider).default_order.to_a
    return if stops.empty? || cats.empty?
    12.times do |i|
      stop = stops[(i * 5) % stops.size]; cat = cats[i % cats.size]; fare = fares[i % [fares.size, 1].max]
      FixedRouteBoarding.create!(run: run, stop: stop, rider_category: cat, fare_type: fare, boarded_count: 1 + (i % 3), alighted_count: i % 2,
                                 fare_amount: (fare && fare.name =~ /cash/i ? 1.0 * (1 + (i % 3)) : nil), client_uuid: "training-#{date}-#{i}",
                                 recorded_at: tz.parse("#{date} 08:00") + (i * 40).minutes)
    end
    puts "  ridership day seeded on #{route.name}: #{run.fixed_route_boardings.sum(:boarded_count)} boarded over 12 walk-ons"
  rescue => e
    puts "  ridership day NOT seeded: #{e.class}: #{e.message[0, 160]}"
  end

  def seed_prior_defect(provider, driver, vehicle, depot, date, tz)
    run = build_training_run(provider, driver, vehicle, depot, date, "#{RUN_PREFIX} 01 (yesterday)", tz)
    run.update_columns(start_odometer: 48210, end_odometer: 48297,
                       actual_start_time: tz.parse("#{date} 08:02"), actual_end_time: tz.parse("#{date} 16:48"), complete: true)
    item = VehicleInspection.where(provider_id: provider.id).where("description ILIKE ?", "%brake%").first ||
           VehicleInspection.where(provider_id: provider.id).first
    return unless item
    report = VehicleInspectionReport.create!(run: run, provider: provider, vehicle: vehicle, driver: driver,
                                             phase: "pre", odometer: 48210, safe_to_operate: true,
                                             submitted_at: tz.parse("#{date} 07:55"), certified_at: tz.parse("#{date} 07:55"))
    report.run_vehicle_inspections.create!(run: run, vehicle_inspection_id: item.id, status: "defect",
                                           defect_note: "Reservoir below MIN line (training example)")
    report.refresh_defects!
    report.push_defects_to_maintenance! if report.has_defects
    puts "  prior defect seeded on unit #{vehicle.name}: #{item.description}"
  rescue => e
    puts "  prior defect NOT seeded: #{e.class}: #{e.message[0, 160]}"
  end
end
