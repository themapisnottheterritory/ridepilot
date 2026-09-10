namespace :fare_cards do
  desc "Pull paid Stripe Payment Link sessions and post them as fare card loads (PROVIDER_ID=1, DAYS=7)"
  task sync_online_reloads: :environment do
    provider = Provider.find(ENV.fetch("PROVIDER_ID") { Provider.where(inactivated_date: nil).order(:id).first!.id })
    sync = StripeReloadSync.new(provider: provider, since: ENV.fetch("DAYS", "7").to_i.days.ago)
    abort "STRIPE_SECRET_KEY is not set; nothing to do." unless sync.configured?
    outcome = sync.run!
    puts "#{Time.current.strftime('%Y-%m-%d %H:%M')} #{provider.name}: #{outcome.summary}"
    outcome.posted.each { |p| puts "  posted   #{p[:session]}  #{p[:customer]}  $#{'%.2f' % p[:amount]}" }
    outcome.unmatched.each { |u| puts "  UNMATCHED #{u[:session]}  card ##{u[:card_number] || '?'}  $#{'%.2f' % u[:amount]}  #{u[:email]}  #{u[:created].strftime('%m/%d %H:%M')}" }
  end
end

namespace :fare_cards do
  desc "Seed the demand-response fare schedule from the published Victoria / DeWitt rural table (PROVIDER_ID=1); refuses to overwrite an existing table unless FORCE=1"
  task seed_schedule: :environment do
    provider = Provider.find(ENV.fetch("PROVIDER_ID") { Provider.where(inactivated_date: nil).order(:id).first!.id })
    schedule = FareSchedule.new(provider)
    abort "#{provider.name} already has #{schedule.rows.size} schedule rows; set FORCE=1 to replace them." if schedule.configured? && ENV["FORCE"] != "1"
    cats = RiderCategory.by_provider(provider).index_by { |c| c.name.downcase }
    find = ->(*names) { names.map { |n| cats[n.downcase] }.compact.first or abort("rider category #{names.first.inspect} not found") }
    youth0 = find.("Youth 0-5", "Child"); youth = find.("Youth 5-17", "Student"); adult = find.("Adult")
    senior = find.("Senior 60+", "Senior", "Elderly"); disabled = find.("Disabled")
    # gcrpc.org, Golden Crescent Transit (Rural) fare schedule, DeWitt & Victoria Counties, read 2026-09-10.
    table = { 5 => [0, 0.75, 1.00, 0.50], 10 => [0, 1.75, 2.00, 1.00], 15 => [0, 2.50, 3.00, 1.50], 20 => [0, 2.50, 4.00, 2.00], nil => [0, 3.00, 5.00, 2.50] }
    grid = table.transform_keys(&:to_s).transform_values { |u5, y, a, e|
      { youth0.id => u5, youth.id => y, adult.id => a, senior.id => e, disabled.id => e }
    }
    schedule.replace!(grid)
    puts "#{provider.name}: #{schedule.rows.size} rows in #{schedule.bands.size} bands"
    schedule.bands.each { |b| puts format("  %-10s %s", (b ? "<= #{b.to_i} mi" : "over"), schedule.rows.select { |r| r.up_to_miles == b }.map { |r| "#{r.rider_category.name} $#{'%.2f' % r.fare}" }.join(", ")) }
  end
end
