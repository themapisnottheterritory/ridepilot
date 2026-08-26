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
# Set CUSTOMER_ID to limit it to one rider -- the orphans belong to whoever
# happened to have a standing trip deleted, so they are rarely all one
# decision, and clearing them a rider at a time is usually the honest way.

apply    = ENV['APPLY'] == '1'
customer = ENV['CUSTOMER_ID'].presence&.to_i

orphans = Trip.where.not(repeating_trip_id: nil)
              .where("pickup_time > ?", Time.current)
              .where("NOT EXISTS (SELECT 1 FROM repeating_trips rt WHERE rt.id = trips.repeating_trip_id)")
orphans = orphans.where(customer_id: customer) if customer

puts(apply ? "APPLYING" : "DRY RUN -- nothing will change (set APPLY=1 to withdraw)")
puts "scope: customer #{customer}" if customer
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
  remaining = Trip.where.not(repeating_trip_id: nil).where('pickup_time > ?', Time.current)
                  .where('NOT EXISTS (SELECT 1 FROM repeating_trips rt WHERE rt.id = trips.repeating_trip_id)')
  puts "future orphans left system-wide: #{remaining.count}"
  remaining.group(:customer_id).count.each { |cid, n| puts "   customer #{cid}: #{n}" }
end
