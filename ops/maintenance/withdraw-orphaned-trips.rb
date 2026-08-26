# Withdraw daily trips whose standing trip no longer exists.
#
# Destroying a RepeatingTrip used to leave its already-generated daily trips on
# the dispatch board, pointing at a template that is gone. Nothing that works
# from the standing trip can see them, so they are only ever noticed on the
# board itself. The model now withdraws them on destroy; this clears the ones
# that accumulated before that fix.
#
# Only FUTURE trips. Past ones are the record of what the service actually did
# and are left exactly as they are. Withdrawal is a soft delete -- every row
# here is recoverable with Trip.only_deleted.
#
# Runs as a dry run. Set APPLY=1 to actually withdraw.

apply = ENV['APPLY'] == '1'

orphans = Trip.where.not(repeating_trip_id: nil)
              .where("pickup_time > ?", Time.current)
              .where("NOT EXISTS (SELECT 1 FROM repeating_trips rt WHERE rt.id = trips.repeating_trip_id)")

puts(apply ? "APPLYING" : "DRY RUN -- nothing will change (set APPLY=1 to withdraw)")
puts

orphans.group_by(&:customer_id).each do |customer_id, trips|
  name = Customer.unscoped.find_by_id(customer_id)&.then { |c| "#{c.first_name} #{c.last_name}" } || "?"
  puts "customer #{customer_id} (#{name}): #{trips.size} orphaned future trips"
  trips.group_by(&:repeating_trip_id).each do |rt_id, ts|
    dates = ts.map { |t| t.pickup_time.to_date }.minmax
    puts "   from deleted standing trip #{rt_id}: #{ts.size} trips, #{dates.first} .. #{dates.last}"
  end
end
puts
puts "total: #{orphans.count}"

if apply
  n = 0
  ActiveRecord::Base.transaction { orphans.find_each { |t| t.destroy; n += 1 } }
  puts "withdrawn: #{n}"
  puts "remaining future orphans: #{
    Trip.where.not(repeating_trip_id: nil).where('pickup_time > ?', Time.current)
        .where('NOT EXISTS (SELECT 1 FROM repeating_trips rt WHERE rt.id = trips.repeating_trip_id)').count}"
end
