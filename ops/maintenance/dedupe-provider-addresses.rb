# Merge provider addresses that are the same place recorded many times.
#
# The Shaw import created one copy of each destination per rider's home town, so
# the city field holds the RIDER's town rather than the destination's. Inteplast
# Plant, 101 Inteplast BLVD, exists seven times -- Victoria, Yoakum, Bay City,
# Blessing, Port Lavaca, El Campo and Lolita -- for one plant, which is in
# Lolita. Liberty Dialysis exists nine times for one clinic.
#
# Only rows whose NAME is a real name are touched. Two thirds of this table is
# named by its own street address, and "1310 E Broadway" is a genuinely
# different building in Cuero and in Victoria; merging on that key would fuse
# unrelated places. Those 42 groups are left alone.
#
# Coordinates cannot be used to confirm a match -- they are too sparse and, where
# present on both sides, usually disagree by more than a kilometre because the
# wrong-city rows geocoded to the wrong town. But their PRESENCE is a good signal
# for which row is right: the geocoder could only resolve the row whose city was
# correct. So the canonical row is the geocoded one, then the most referenced,
# then the oldest.
#
# Losers are soft-deleted, never destroyed, and every reference is repointed
# first. Trip history keeps pointing at a real address.
#
# Dry run unless APPLY=1.

apply = ENV['APPLY'] == '1'

FKS = [
  ['trips', 'pickup_address_id'], ['trips', 'dropoff_address_id'],
  ['repeating_trips', 'pickup_address_id'], ['repeating_trips', 'dropoff_address_id'],
  ['itineraries', 'address_id'], ['repeating_itineraries', 'address_id'],
  ['travel_time_estimates', 'from_address_id'], ['travel_time_estimates', 'to_address_id'],
  ['customers', 'address_id'],
].freeze

def norm(s)
  s.to_s.upcase.gsub(/[^A-Z0-9]/, '')
end

def refcount(id)
  FKS.sum { |t, c| ActiveRecord::Base.connection.select_value("SELECT count(*) FROM #{t} WHERE #{c} = #{id.to_i}").to_i }
end

rows = Address.where(deleted_at: nil, type: 'ProviderCommonAddress').to_a
groups = rows.group_by { |a| [norm(a.name), norm(a.address)] }
           .select { |(n, _), v| v.size > 1 && !n.empty? }
           .reject { |_, v| v.any? { |a| a.name.to_s =~ /\A\s*\d/ } }   # street-address names

plan = groups.map do |_, members|
  keeper = members.min_by { |a| [a.the_geom ? 0 : 1, -refcount(a.id), a.id] }
  [keeper, members - [keeper]]
end

moves = plan.sum { |_, losers| losers.sum { |l| refcount(l.id) } }
puts(apply ? 'APPLYING' : 'DRY RUN -- nothing will change (set APPLY=1)')
puts
puts "groups        : #{plan.size}"
puts "rows retired  : #{plan.sum { |_, l| l.size }}"
puts "refs repointed: #{moves}"
puts
plan.sort_by { |_, l| -l.size }.first(6).each do |keeper, losers|
  puts "#{keeper.name} -- #{keeper.address}"
  puts "   KEEP  #{keeper.id} #{keeper.city} #{keeper.zip} #{keeper.county} #{keeper.the_geom ? '(geocoded)' : ''} refs=#{refcount(keeper.id)}"
  losers.each { |l| puts "   drop  #{l.id} #{l.city} #{l.zip} #{l.county} refs=#{refcount(l.id)}" }
end

exit unless apply

ActiveRecord::Base.transaction do
  plan.each do |keeper, losers|
    losers.each do |l|
      FKS.each { |t, c| ActiveRecord::Base.connection.execute("UPDATE #{t} SET #{c} = #{keeper.id} WHERE #{c} = #{l.id}") }
      l.destroy   # acts_as_paranoid: recoverable
    end
  end
end

puts
puts 'done.'
puts "provider addresses live: #{Address.where(deleted_at: nil, type: 'ProviderCommonAddress').count}"
puts "orphaned references: #{FKS.sum { |t,c| ActiveRecord::Base.connection.select_value(
  "SELECT count(*) FROM #{t} x JOIN addresses a ON a.id=x.#{c} WHERE a.deleted_at IS NOT NULL").to_i }}"
