# The footer line on every page: a kind quote of the day (config/footer_quotes.yml)
# and, once there is something to count, the rides the signed-in provider
# completed today.
#
# "Completed" is the trip result Complete, which the driver's tablet sets when
# the drop-off is marked done (dispatch can also set it). A ride nobody marked
# is not counted, so the number can run low but never high.
class FooterNote
  QUOTES_FILE = Rails.root.join("config", "footer_quotes.yml")

  # Same quote for everyone all day; the next one tomorrow.
  def self.quote(date = Time.zone.today)
    quotes = Array(YAML.safe_load(File.read(QUOTES_FILE))).map(&:to_s).reject(&:blank?)
    quotes.empty? ? "" : quotes[date.jd % quotes.size]
  rescue Errno::ENOENT, Psych::SyntaxError
    ""
  end

  def self.rides_completed(provider, date = Time.zone.today)
    return 0 unless provider
    Trip.completed.where(provider_id: provider.id, pickup_time: date.in_time_zone.all_day).count
  end

  # nil when there is nothing to report yet, so the footer shows only the quote
  def self.rides_text(count)
    return nil unless count.to_i > 0
    count == 1 ? "Today so far: 1 ride got a neighbor where they chose to go." :
                 "Today so far: #{count} rides got neighbors where they chose to go."
  end
end
