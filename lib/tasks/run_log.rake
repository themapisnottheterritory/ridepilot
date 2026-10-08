# Builds Vehicle Summary by Run (RunLogReport) days ahead of time, so the
# report opens without waiting on GPS. Cron on .16, nightly:
#   rake run_log:warm            # yesterday and the day before, every agency
#   rake run_log:warm DAYS=92    # backfill
namespace :run_log do
  task warm: :environment do
    days = (ENV["DAYS"] || 2).to_i
    Provider.where(id: Run.where(date: (Date.current - days)...Date.current).distinct.select(:provider_id)).find_each do |p|
      gps = GpsMiles.new(p)
      compare = FixedRouteRows.fetcher
      ((Date.current - days)...Date.current).each do |day|
        t0 = Time.now
        RunLogReport.build_day!([p.id], day, gps: gps, compare: compare)
        puts "#{Time.now.strftime('%F %T')} run_log #{p.name} #{day} #{(Time.now - t0).round(1)} s"
      end
    end
  end
end
