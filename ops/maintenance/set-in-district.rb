# Populate in_district from the eight-county service area.
#
# in_district was never computed. Address#compute_in_district is marked
# deprecated and its body is a commented-out PostGIS test against a primary
# Region -- and the regions table is empty, so nothing ever ran. Only seven
# addresses have ever carried the flag, six set the day the system was stood up
# in February 2023 and one a test of Phil's house that September.
#
# That is not a cosmetic gap. TripCore#is_in_district? requires BOTH ends of a
# trip to be flagged, so with nil everywhere the Service Summary has been
# reporting every trip, of every purpose, as out of district. A wrong number
# rather than a missing one.
#
# The rule is the service area: an address is in district when its county is one
# of the eight. County reaches provider addresses from the group it used to be
# stored in; customer addresses get it here, from their city.
#
# Ambiguity is handled rather than averaged. A county is only believed for a city
# if it accounts for at least MIN_SHARE of that city's known addresses -- which
# drops the two rows filing Yoakum city under Yoakum County (west Texas) and
# would have dropped Gonzales under Harris. Where a city still maps to more than
# one county, in_district is set only if every candidate agrees; Yoakum straddles
# the DeWitt/Lavaca line and both are in district, so it resolves cleanly.
#
# Where no county can be determined, in_district is left nil. Unspecified is a
# truthful answer and the table now renders it as one.
#
# Dry run unless APPLY=1.

SERVICE_AREA = ['Calhoun', 'Dewitt', 'Goliad', 'Gonzales', 'Jackson',
                'Lavaca', 'Victoria', 'Matagorda'].map(&:downcase).freeze
MIN_SHARE = 0.05

# Counties whose rows are known to be corrupt, and which therefore get no
# verdict at all. Yoakum's thirteen sit in Denver City and Plains, both real
# Yoakum County towns 400 miles west -- but they are named "Cuero Devita
# Dialysis", "Cuero Nursing And Rehab" and "Walmart(dew)", which are Cuero and
# DeWitt businesses. The city is wrong, not the geography, and calling them out
# of district would be as confidently wrong as the nil they replace.
SUSPECT_COUNTIES = ['yoakum'].freeze

apply = ENV['APPLY'] == '1'

# city -> counties worth believing
counts = Hash.new { |h, k| h[k] = Hash.new(0) }
Address.where(deleted_at: nil).where.not(county: nil).where.not(city: nil)
       .pluck(:city, :county).each { |city, county| counts[city.strip.downcase][county.strip] += 1 }

city_counties = {}
counts.each do |city, tally|
  total = tally.values.sum
  kept  = tally.select { |_, n| n.to_f / total >= MIN_SHARE }.keys
  city_counties[city] = kept unless kept.empty?
end

def verdict(counties)
  flags = counties.map { |c| SERVICE_AREA.include?(c.downcase) }.uniq
  flags.size == 1 ? flags.first : nil     # mixed -> no opinion
end

set_county = {}
set_flag   = {}
suspect    = []
Address.where(deleted_at: nil).where.not(city: nil)
       .pluck(:id, :city, :county, :in_district).each do |id, city, county, flag|
  candidates = county ? [county] : city_counties[city.strip.downcase]
  next if candidates.nil? || candidates.empty?
  if candidates.any? { |c| SUSPECT_COUNTIES.include?(c.downcase) }
    suspect << [id, city, county]
    next
  end
  set_county[id] = candidates.first if county.nil? && candidates.size == 1
  v = verdict(candidates)
  set_flag[id] = v unless v.nil? || v == flag
end

puts(apply ? 'APPLYING' : 'DRY RUN -- nothing will change (set APPLY=1)')
puts
puts "service area          : #{SERVICE_AREA.map(&:capitalize).join(', ')}"
puts "city -> county map    : #{city_counties.size} cities"
puts "counties to backfill  : #{set_county.size}"
puts "in_district to set    : #{set_flag.size}  (#{set_flag.values.count(true)} in, #{set_flag.values.count(false)} out)"
puts
puts "left for a human -- county known to be corrupt (#{suspect.size}):"
suspect.each { |id, city, county| puts "  address #{id} #{city} / #{county}" }
puts
puts 'cities mapping to more than one county:'
city_counties.select { |_, v| v.size > 1 }.each { |c, v| puts "  #{c}: #{v.join(', ')} -> #{verdict(v).inspect}" }

exit unless apply

ActiveRecord::Base.transaction do
  set_county.group_by { |_, c| c }.each { |c, rows| Address.where(id: rows.map(&:first)).update_all(county: c) }
  set_flag.group_by { |_, v| v }.each   { |v, rows| Address.where(id: rows.map(&:first)).update_all(in_district: v) }
end

puts
puts 'done.'
Address.where(deleted_at: nil).group(:in_district).count.each { |k, n| puts format('  in_district %-13s %d', k.inspect, n) }
