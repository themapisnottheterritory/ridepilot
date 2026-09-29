# Numbers for the I.T. trouble board (/trouble_board): TroubleWatch's events
# plus the Ask RidePilot answers that fell short, for the last N days, with
# the N days before for comparison. Everything is counted by screen.
class TroubleBoard
  RANGES = [7, 30, 90].freeze
  KINDS = {
    "error"   => { label: "Errors",            color: "#c0392b", blurb: "Pages that broke or saves that failed" },
    "message" => { label: "Refusals",          color: "#d68910", blurb: "Messages people hit when RidePilot said no" },
    "slow"    => { label: "Slow pages",        color: "#2e86c1", blurb: "Pages that took #{TroubleWatch::SLOW_MS / 1000} seconds or more" },
    "help"    => { label: "Ask RidePilot misses", color: "#7d3c98", blurb: "Answers that were unsure, failed, or got a thumbs down" }
  }.freeze
  LOCAL_DAY = "date(%s AT TIME ZONE 'UTC' AT TIME ZONE 'America/Chicago')".freeze
  HELP_MISS = "(help_questions.helpful = false OR help_questions.error IS NOT NULL OR " \
              "help_questions.answer ILIKE '%not sure%' OR help_questions.answer ILIKE '%no estoy segur%')".freeze

  attr_reader :days, :provider_id, :today, :first_day

  def initialize(days: 7, provider_id: nil)
    @days = RANGES.include?(days.to_i) ? days.to_i : 7
    @provider_id = provider_id.presence&.to_i
    @today = Time.zone.today
    @first_day = @today - (@days - 1)
  end

  def dates
    (first_day..today).to_a
  end

  def period_start
    first_day.in_time_zone.beginning_of_day
  end

  def previous_start
    (first_day - days).in_time_zone.beginning_of_day
  end

  # { "error" => { count:, previous:, daily: [..one per date..] }, ... }
  def summary
    @summary ||= KINDS.keys.index_with do |kind|
      scope = kind == "help" ? help_scope : events.where(kind: kind)
      table = kind == "help" ? "help_questions" : "trouble_events"
      by_day = scope.where("#{table}.created_at >= ?", period_start)
                    .group(Arel.sql(format(LOCAL_DAY, "#{table}.created_at"))).count
      { count: by_day.values.sum,
        previous: scope.where("#{table}.created_at >= ? AND #{table}.created_at < ?", previous_start, period_start).count,
        daily: dates.map { |d| by_day[d] || 0 } }
    end
  end

  def total
    summary.values.sum { |s| s[:count] }
  end

  # the most frequent errors: screen, action, what broke, how often, when last
  def errors
    top(events.where(kind: "error"), %i[screen action detail])
  end

  def refusals
    top(events.where(kind: "message"), %i[detail screen])
  end

  def slow_pages
    rows = current(events.where(kind: "slow")).group(:screen, :action)
             .order(Arel.sql("count(*) DESC")).limit(12)
             .pluck(:screen, :action, Arel.sql("count(*)"),
                    Arel.sql("percentile_cont(0.5) WITHIN GROUP (ORDER BY duration_ms)"), Arel.sql("max(duration_ms)"),
                    Arel.sql("max(trouble_events.created_at)"))
    rows.map { |s, a, n, median, worst, last| { screen: s, action: a, count: n, median_s: median.to_f / 1000, worst_s: worst.to_f / 1000, last: last } }
  end

  # Ask RidePilot misses grouped by the screen they were asked from, with the
  # latest few questions (no names)
  def help_misses
    recent = help_scope.where("help_questions.created_at >= ?", period_start).order(created_at: :desc).limit(400)
                       .pluck(:page_path, :question, :helpful, :error, :created_at)
    recent.group_by { |path, *| TroubleWatch.screen_for_path(path) || "Unknown page" }
          .map { |screen, qs| { screen: screen, count: qs.size, questions: qs.first(3).map { |_, q, helpful, err, at| { text: q, why: err ? "failed" : (helpful == false ? "thumbs down" : "unsure"), at: at } } } }
          .sort_by { |g| -g[:count] }
  end

  def screens_hit
    events.where("created_at >= ?", period_start).distinct.count(:screen)
  end

  private

  def events
    scope = TroubleEvent.all
    provider_id ? scope.where(provider_id: provider_id) : scope
  end

  def help_scope
    scope = HelpQuestion.where(HELP_MISS)
    provider_id ? scope.where(provider_id: provider_id) : scope
  end

  def current(scope)
    scope.where("trouble_events.created_at >= ?", period_start)
  end

  # grouped counts, newest-last-seen, plus a daily series for a sparkline
  def top(scope, columns)
    groups = current(scope).group(*columns).order(Arel.sql("count(*) DESC")).limit(12)
                           .pluck(*columns, Arel.sql("count(*)"), Arel.sql("max(trouble_events.created_at)"))
    groups.map do |row|
      key = columns.zip(row).to_h
      daily = current(scope).where(key).group(Arel.sql(format(LOCAL_DAY, "trouble_events.created_at"))).count
      key.merge(count: row[-2], last: row[-1], daily: dates.map { |d| daily[d] || 0 })
    end
  end
end
