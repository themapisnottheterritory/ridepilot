# Give imported drivers the user accounts they need to exist and to log in.
#
# The drivers came across from Shaw straight into the drivers table, carrying
# user ids from the pre-2025 users table. Those users were never migrated, so
# every driver but one points at a row that is simply not there: the profile
# page raised on it, and Driver validates :user, presence: true, so the records
# cannot be edited either.
#
# The driver data itself is sound -- names, phones and addresses all came over.
# What is missing is the account, and RidePilot authenticates by USERNAME, not
# email (config.authentication_keys = [:username]; the driver API looks a driver
# up with User.find_by(username:)). Nothing in the app emails a driver -- both
# sends in UsersController#create_user are commented out -- so the address only
# has to satisfy Devise, and these are deliberately non-routable. A driver who
# forgets a password gets it reset by a dispatcher rather than by mail.
#
# Usernames follow the convention already in the users table -- andrewv,
# kristiek, kellyb -- first name plus last initial, and the 51 imported drivers
# happen to produce 51 distinct ones. A driver who already has a staff account
# under the same name is linked to it rather than given a second.
#
# Dry run unless APPLY=1. Set ONLY_ACTIVE=0 to include inactive drivers.
# Passwords are written to a 0600 file, never to the terminal.

require 'fileutils'

apply       = ENV['APPLY'] == '1'
only_active = ENV['ONLY_ACTIVE'] != '0'
domain      = ENV['DRIVER_EMAIL_DOMAIN'] || 'drivers.gcrpc.org'
outfile     = ENV['CREDENTIALS_FILE'] || "/var/www/ridepilot/tmp/driver-credentials.txt"

scope = Driver.where(deleted_at: nil)
scope = scope.where(active: true) if only_active

def username_for(name, taken)
  parts = name.to_s.strip.split(/\s+/)
  first = parts.first.to_s.downcase.gsub(/[^a-z]/, '')
  last  = parts.last.to_s.downcase.gsub(/[^a-z]/, '')
  base  = "#{first}#{last[0]}"
  base = "driver" if base.strip.empty?
  candidate = base
  n = 1
  while taken.include?(candidate)
    n += 1
    candidate = "#{base}#{n}"
  end
  candidate
end

taken = User.unscoped.pluck(:username).compact.map(&:downcase).to_set
plan  = []

scope.order(:id).each do |d|
  if d.user_id && User.unscoped.exists?(id: d.user_id, deleted_at: nil)
    plan << [d, :ok, nil]
    next
  end
  parts = d.name.to_s.strip.split(/\s+/)
  match = User.where(deleted_at: nil)
              .where("lower(first_name) = ? AND lower(last_name) = ?",
                     parts.first.to_s.downcase, parts.last.to_s.downcase).first
  if match
    plan << [d, :link, match]
  else
    uname = username_for(d.name, taken)
    taken << uname
    plan << [d, :create, uname]
  end
end

puts(apply ? "APPLYING" : "DRY RUN -- nothing will change (set APPLY=1)")
puts "scope: #{only_active ? 'active drivers' : 'all drivers'} (#{scope.count})"
puts

plan.group_by { |(_, action, _)| action }.each do |action, rows|
  puts "#{action.to_s.upcase} (#{rows.size})"
  rows.each do |d, _, extra|
    case action
    when :ok     then puts "   driver #{d.id} #{d.name} -- already linked to user #{d.user_id}"
    when :link   then puts "   driver #{d.id} #{d.name} -> existing user #{extra.id} (#{extra.username})"
    when :create then puts "   driver #{d.id} #{d.name} -> new user #{extra} <#{extra}@#{domain}>"
    end
  end
  puts
end

exit unless apply

created = []
ActiveRecord::Base.transaction do
  plan.each do |d, action, extra|
    case action
    when :link
      d.update_columns(user_id: extra.id, updated_at: Time.current)
    when :create
      parts = d.name.to_s.strip.split(/\s+/)
      password = User.generate_password
      u = User.new(
        first_name: parts.first,
        last_name:  parts[1..].join(' ').presence || parts.first,
        username:   extra,
        email:      "#{extra}@#{domain}",
        phone_number: d.phone_number
      )
      u.password = password
      u.current_provider_id = d.provider_id
      u.save!
      Role.create!(user: u, provider_id: d.provider_id, level: Role::USER_LEVEL)
      d.update_columns(user_id: u.id, updated_at: Time.current)
      created << [d.name, extra, password]
    end
  end
end

if created.any?
  FileUtils.mkdir_p(File.dirname(outfile))
  File.open(outfile, File::WRONLY | File::CREAT | File::TRUNC, 0600) do |f|
    f.puts "RidePilot driver logins -- generated #{Time.current}"
    f.puts "Log in with the USERNAME, not the email address."
    f.puts
    created.each { |name, uname, pw| f.puts format("%-24s %-16s %s", name, uname, pw) }
  end
  File.chmod(0600, outfile)
end

puts "linked:  #{plan.count { |(_, a, _)| a == :link }}"
puts "created: #{created.size}"
puts "credentials written to #{outfile} (mode 0600)" if created.any?
puts
puts "drivers still without a reachable user: #{
  Driver.where(deleted_at: nil).where(active: true).reject { |d|
    d.user_id && User.unscoped.exists?(id: d.user_id, deleted_at: nil) }.size}"
