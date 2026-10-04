# The morning tap check (rake tap_check:report): runs where stops weren't tapped as
# they happened (TapCheck). To dispatch's supervisor (Kristie), copy to Philz.
class TapCheckMailer < ActionMailer::Base
  default from: ENV["SYSTEM_SEND_FROM_ADDRESS"]
  TO = ENV.fetch("TAP_CHECK_TO", "kristiek@gcrpc.org")
  CC = ENV.fetch("TAP_CHECK_CC", "philz@gcrpc.org")

  def day(date, runs)
    @date = date
    @look = runs.select(&:issues?)
    @fine = runs.count { |r| !r.issues? && r.unchecked.zero? }
    @partly = runs.count { |r| !r.issues? && r.unchecked.positive? }
    @unchecked = runs.sum(&:unchecked)
    mail(to: TO, cc: CC,
         subject: "[RidePilot] Tablet stop check, #{date.strftime('%a %b %-d')}: " +
                  (@look.any? ? "#{@look.size} run#{'s' unless @look.size == 1} worth a look" : "nothing to look at"))
  end
end
