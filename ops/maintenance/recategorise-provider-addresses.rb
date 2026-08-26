# Move county out of address_group and put the categories back in it.
#
# address_group is the address TYPE everywhere else in the code:
# AddressGroup::UNKNOWN_TYPE is 'Needs Update', and ReportsController labels the
# filter "Address Type". Eight categories were created for it -- Medical,
# Dialysis, Retail & Grocery, Employment, Government & Social Services,
# Education, Senior Center, Transit -- and never used, because 34 counties were
# sitting in the field instead.
#
# County now has its own column (see the AddCountyToAddresses migration), so:
#
#   1. copy the county out of the group, verbatim -- no majority-voting, because
#      Yoakum straddles the DeWitt/Lavaca line and an 87/29 split there is real
#      geography rather than a mistake
#   2. correct only what cannot be anything but wrong
#   3. classify by name, and only for places actually NAMED like places: two
#      thirds of these rows are called things like "3208 Bobolink", which is a
#      house, and no category will ever fit one
#   4. everything else goes to 'Needs Update', which is what it is for
#
# Dry run unless APPLY=1.

apply = ENV['APPLY'] == '1'

CATEGORIES = [
  # Ordered: first match wins, so the specific beats the general. A dialysis
  # centre is Dialysis before it is Medical; a nursing home is a Senior Center
  # before it is Medical.
  ['Dialysis',                     /dialysis|davita|fresenius|kidney/i],
  ['Senior Center',                /senior|nursing home|nursing center|assisted living|retirement|adult day|elder/i],
  ['Education',                    /school|college|university|academy|\bisd\b|campus|head start|daycare|day care/i],
  ['Transit',                      /transit|greyhound|airport|bus station|\bdepot\b/i],
  # No bare \bcounty\b: it catches "County RD 237" (a road) and "Home-Goliad
  # County" (a house) as readily as a courthouse. No \bva\b either -- its only
  # match here is "VA Clinic", which belongs in Medical and lands there on its
  # own. Both would rather be Needs Update than confidently wrong.
  ['Government & Social Services', /court|city hall|social security|\bdshs\b|\bdps\b|post office|library|police|sheriff|housing authority|food bank|salvation army|goodwill|veteran|workforce/i],
  ['Employment',                   /employment|staffing|\bjobs?\b/i],
  ['Medical',                      /hospital|clinic|medical|health|physician|surgery|surgical|dental|dentist|orthope|cardio|oncolog|cancer|imaging|radiolog|pharmac|therapy|rehab|urgent care|vision|hearing|pediatric|wellness|care center|\bdoctor/i],
  ['Retail & Grocery',             /walmart|wal-mart|h-e-b|\bheb\b|kroger|dollar|grocery|market|mall|store|shop|target|aldi|brookshire|salon|barber|restaurant|cafe|mcdonald|whataburger/i],
].freeze

CATEGORY_NAMES = CATEGORIES.map(&:first).freeze
unknown = AddressGroup.find_by_name(AddressGroup::UNKNOWN_TYPE) or abort "no 'Needs Update' group"
groups  = AddressGroup.where(name: CATEGORY_NAMES).index_by(&:name)
missing = CATEGORY_NAMES - groups.keys
abort "missing category groups: #{missing.inspect}" if missing.any?

addresses = Address.where(deleted_at: nil, type: 'ProviderCommonAddress').includes(:address_group)

county_of  = {}
category_of = {}
anomalies  = []

addresses.each do |a|
  group = a.address_group&.name

  # 1 + 2. county, verbatim, unless it cannot be right
  unless group.nil? || group == AddressGroup::UNKNOWN_TYPE || CATEGORY_NAMES.include?(group)
    county = group
    if a.city.to_s.casecmp('Gonzales').zero? && %w[Harris Guadalupe].include?(group)
      anomalies << "  address #{a.id} #{a.name.to_s[0,30]} (#{a.city}) county #{group} -> Gonzales"
      county = 'Gonzales'
    elsif a.city.to_s.casecmp('Yoakum').zero? && group == 'Yoakum'
      anomalies << "  address #{a.id} #{a.name.to_s[0,30]} (#{a.city}) county 'Yoakum' is west Texas -- LEFT AS IS, needs a human"
    end
    county_of[a.id] = county
  end

  # 3. classify, names only -- a row called "498 AVE B" is a house
  next if a.name.to_s =~ /\A\s*\d/
  hit = CATEGORIES.find { |_, re| a.name =~ re }
  category_of[a.id] = groups[hit.first] if hit
end

puts(apply ? 'APPLYING' : 'DRY RUN -- nothing will change (set APPLY=1)')
puts
puts "provider addresses          : #{addresses.size}"
puts "county backfilled from group: #{county_of.size}"
puts "classified into a category  : #{category_of.size}"
puts "left on 'Needs Update'      : #{addresses.size - category_of.size}"
puts
puts 'by category:'
category_of.values.group_by(&:name).sort_by { |_, v| -v.size }.each { |n, v| puts format('  %-30s %d', n, v.size) }
puts
puts "anomalies corrected or flagged (#{anomalies.size}):"
puts anomalies

exit unless apply

ActiveRecord::Base.transaction do
  county_of.each_slice(500) do |slice|
    slice.each { |id, c| Address.where(id: id).update_all(county: c) }
  end
  addresses.each do |a|
    target = category_of[a.id] || unknown
    Address.where(id: a.id).update_all(address_group_id: target.id) if a.address_group_id != target.id
  end
  # The counties were only ever in this table because they had nowhere else to
  # be. Leaving them would put 34 counties back in the category picker.
  AddressGroup.where.not(name: CATEGORY_NAMES + [AddressGroup::UNKNOWN_TYPE]).destroy_all
end

puts
puts 'done.'
puts "groups remaining: #{AddressGroup.order(:name).pluck(:name).join(', ')}"
puts "addresses with a county: #{Address.where(type: 'ProviderCommonAddress', deleted_at: nil).where.not(county: nil).count}"
