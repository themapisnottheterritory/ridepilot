# Correct the thirteen addresses stranded in Yoakum County, west Texas.
#
# They were geocoded from a city of "Yoakum" and the geocoder took the county
# 400 miles away rather than the town in DeWitt/Lavaca, writing back Denver City
# and Plains -- real Yoakum County towns -- along with west Texas coordinates.
#
# Two facts are solid. ZIP 77995 is Yoakum, TX, which is in district. And every
# address sharing these street addresses elsewhere in the table sits in DeWitt or
# Lavaca. Nothing here is in west Texas.
#
# The city field is NOT repaired from twins, because city is corrupt across this
# whole table in a different way: the same destination is duplicated once per
# rider's home town, so "Cuero Davita Dialysis, 1105 E Broadway" also appears
# under Fannin, Nordheim, Yorktown and Shiner. A twin's city is another rider's
# town, not the destination's, so copying it would swap one wrong answer for
# another.
#
# Instead the name is used where it states the town outright -- five of these say
# Cuero, and "Walmart(dew)" says DeWitt -- and the ZIP is used for the rest.
#
# Geometry is cleared rather than corrected. It points at west Texas and is
# certainly wrong; nil lets the app geocode it properly on next save, which is
# better than a coordinate invented here.
#
# Dry run unless APPLY=1.

apply = ENV['APPLY'] == '1'

CUERO  = { city: 'Cuero',  zip: '77954', county: 'Dewitt' }   # named for the town
YOAKUM = { city: 'Yoakum', zip: '77995', county: 'Lavaca' }   # per ZIP 77995

rows = Address.where(deleted_at: nil, county: 'Yoakum').order(:id)
abort "expected 13, found #{rows.size}" unless rows.size == 13

plan = rows.map do |a|
  says_cuero = a.name.to_s =~ /cuero|\(dew\)/i || a.address.to_s =~ /E Broadway/i
  [a, says_cuero ? CUERO : YOAKUM, says_cuero ? 'name/address says Cuero' : 'ZIP 77995 = Yoakum, TX']
end

puts(apply ? 'APPLYING' : 'DRY RUN -- nothing will change (set APPLY=1)')
puts
plan.each do |a, t, why|
  puts format('  %-7d %-24s %-12s -> %-8s %-6s %-8s  (%s)',
              a.id, a.name.to_s[0,24], a.city, t[:city], t[:zip], t[:county], why)
end
puts
puts "all thirteen become in_district = true; west Texas geometry cleared for re-geocoding"

exit unless apply

ActiveRecord::Base.transaction do
  plan.each do |a, t, _|
    Address.where(id: a.id).update_all(
      city: t[:city], zip: t[:zip], county: t[:county],
      in_district: true, the_geom: nil, updated_at: Time.current)
  end
end

puts
puts 'done.'
Address.where(id: plan.map { |a, _, _| a.id }).order(:id).each do |a|
  puts format('  %-7d %-24s %-8s %-6s %-8s in_district=%s geom=%s',
              a.id, a.name.to_s[0,24], a.city, a.zip, a.county, a.in_district, a.the_geom.nil? ? 'nil' : 'set')
end
puts "addresses left in Yoakum County: #{Address.where(deleted_at: nil, county: 'Yoakum').count}"
