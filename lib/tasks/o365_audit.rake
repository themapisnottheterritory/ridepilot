namespace :o365 do
  desc "READ-ONLY audit of web-user email readiness for Entra/O365 SSO. " \
       "Sizes who can SSO (tenant-domain UPN) vs who must stay on password. " \
       "Usage: rake o365:email_audit [TENANT=gcrpc.org]"
  task email_audit: :environment do
    tenant = (ENV["TENANT"] || "gcrpc.org").downcase
    placeholder_domains = %w[example.com example.org test.com localhost local invalid noemail.com none.com]

    placeholder = lambda do |email|
      next true if email.blank?
      e = email.downcase
      next true if placeholder_domains.any? { |d| e.end_with?("@#{d}") || e.end_with?(".#{d}") }
      next true if e.match?(/noemail|no-email|placeholder|example/)
      next true unless e.match?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/) # not a well-formed address
      false
    end

    web_user_ids = Role.distinct.pluck(:user_id)
    web_users    = User.where(id: web_user_ids)
    total        = web_users.count

    puts "=" * 68
    puts "O365 / ENTRA EMAIL-READINESS AUDIT   (env=#{Rails.env}, tenant=#{tenant})"
    puts "READ-ONLY — no data is modified."
    puts "=" * 68
    puts "Total non-deleted users ............... #{User.count}"
    puts "Web users (hold a Role) ............... #{total}"
    puts "Users with a Driver record ............ #{User.joins(:driver).count}"
    puts "  ...also web users ................... #{User.joins(:driver).where(id: web_user_ids).count}"
    puts "  ...driver-only (no Role) ............ #{User.joins(:driver).where.not(id: web_user_ids).count}"
    puts

    blank = 0; ph = 0; tenant_ok = 0; other_real = 0
    domains = Hash.new(0)
    web_users.find_each do |u|
      if u.email.blank?
        blank += 1; ph += 1; next
      elsif placeholder.call(u.email)
        ph += 1; next
      end
      dom = u.email.downcase.split("@").last
      domains[dom] += 1
      dom == tenant ? tenant_ok += 1 : other_real += 1
    end

    pct = total.zero? ? 0 : (100.0 * tenant_ok / total).round(1)
    puts "-- Web-user email quality --"
    puts "Blank ................................. #{blank}"
    puts "Placeholder / malformed (incl. blank) . #{ph}"
    puts "Real, on tenant #{tenant} (CAN SSO) ... #{tenant_ok}"
    puts "Real, other domain (password-only) .... #{other_real}"
    puts
    puts ">> SSO-eligible: #{tenant_ok}/#{total} web users (#{pct}%) on #{tenant}."
    puts ">> Password-only: #{ph + other_real} (placeholder/malformed or non-tenant domain)."
    puts

    dupes = web_users.where.not(email: [nil, ""]).group("lower(email)").having("count(*) > 1").count
    puts "-- Duplicate emails among web users (would break UPN matching) --"
    dupes.empty? ? (puts "  none") : dupes.each { |e, c| puts "  #{e} -> #{c} users" }
    puts

    puts "-- Domain distribution (web users, real emails) --"
    domains.sort_by { |_, c| -c }.each do |d, c|
      puts format("  %-34s %d%s", d, c, (d == tenant ? "  <- tenant" : ""))
    end
    puts
    puts "The 'password-only' set is who keeps username/password after SSO is enabled."
  end
end
