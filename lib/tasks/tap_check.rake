namespace :tap_check do
  # Morning tap check for yesterday (TapCheck): cron on .16 at 11:15 UTC = 6:15 AM
  # Central. DATE=YYYY-MM-DD for another day; DRY=1 prints instead of emailing.
  desc "Email dispatch's supervisor the runs whose stops weren't tapped as they happened"
  task report: :environment do
    date = ENV["DATE"].present? ? Date.parse(ENV["DATE"]) : Date.current - 1
    runs = TapCheck.day(date)
    if runs.empty?
      puts "#{Time.current.strftime('%F %T')} #{date}: no runs"
      next
    end
    mail = TapCheckMailer.day(date, runs)
    if ENV["DRY"].present?
      puts mail.subject, mail.body.decoded
    else
      mail.deliver_now
      puts "#{Time.current.strftime('%F %T')} #{date}: sent (#{runs.count(&:issues?)} to look at of #{runs.size})"
    end
  end
end
