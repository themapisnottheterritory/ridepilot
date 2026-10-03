namespace :driver_stops do
  # Where drivers stop (DriverStops): for each finished pickup and drop-off, where the
  # van sat still, from the bus GPS on .40. Nightly on .16 at 07:30 UTC = 2:30 AM
  # Central for yesterday and today; FROM=YYYY-MM-DD to fill in from a date.
  desc "Record where vans stopped for finished pickups and drop-offs"
  task record: :environment do
    from = ENV["FROM"].present? ? Date.parse(ENV["FROM"]) : Date.current - 1
    (from..Date.current).each do |d|
      n = DriverStops.record_day!(d)
      puts "#{Time.current.strftime('%F %T')} #{d}: #{n} stops recorded"
    end
    puts "#{Time.current.strftime('%F %T')} addresses with a learned spot: #{DriverStops.learned.size}"
  end
end
