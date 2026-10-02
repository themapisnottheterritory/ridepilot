namespace :tablets do
  desc "Drop tablet reports older than 90 days (the Tablets page keeps each tablet's latest)"
  task prune: :environment do
    n = TabletPing.where("at < ?", 90.days.ago).delete_all
    puts "tablets:prune removed #{n} old reports"
  end
end
