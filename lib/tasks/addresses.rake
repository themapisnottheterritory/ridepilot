namespace :addresses do
  # Morning address check (AddressScan): emails GCRPC I.T. what is new since
  # the last run (the first run sends everything, as a starting list), and
  # nothing when nothing is new. Remembers what it has reported in
  # tmp/address_scan_seen.json. Cron on .16 at 10:45 UTC = 5:45 AM Central (the server clock is UTC).
  desc "Scan saved addresses and upcoming trips; email I.T. anything new"
  task scan: :environment do
    state = Rails.root.join("tmp", "address_scan_seen.json")
    seen = state.exist? ? JSON.parse(state.read) : nil
    findings = AddressScan.new.findings
    fresh = seen ? findings.reject { |f| seen.include?(f.key) } : findings
    puts "#{Time.current}: #{findings.size} open, #{fresh.size} new"
    AddressScanMailer.new_findings(fresh, findings.size, first_run: seen.nil?).deliver_now if fresh.any?
    state.write(JSON.generate(findings.map(&:key)))
  end
end
