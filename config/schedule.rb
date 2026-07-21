# Cron job scheduler. Integrates with Capistrano, or update your custom 
# deployments to manually execute whenever 'bundle exec whenever --update-crontab'. 
# See `bundle exec whenever --help` for details

every 1.day, :at => '12:00 am' do
  rake "scheduler:run"
end

every 1.day, :at => '6:00 pm' do
  runner "DayBeforeReminderJob.perform_later"
end

every 1.day, :at => '11:00 pm' do
  runner "OvernightOptimizeJob.perform_later"
end
