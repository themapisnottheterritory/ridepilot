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
