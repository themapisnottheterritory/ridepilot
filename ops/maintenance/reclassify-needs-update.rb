# Second classification pass, over the rows still on Needs Update.
#
# The first pass read names for what a place IS, and most places do not say.
# "Detar Family Medicine Center" missed a rule looking for "medical"; Bay City
# High School is written "Bchs"; a rider going to Burger King is going shopping
# as far as a schedule is concerned. This widens the rules and, where the eight
# categories genuinely had no home for something, follows a decision rather than
# inventing a category:
#
#   Retail & Grocery is all shopping and personal errands -- shops, groceries,
#   restaurants, salons, gyms, hotels. From dispatch they are one kind of trip.
#
#   Churches join Government & Social Services as community destinations.
#
# It only touches rows currently on Needs Update, so nothing already categorised
# -- by the first pass or by hand -- can be overwritten.
#
# Residential rows are never classified. "Home-Dewitt", "Home(rv Park)" and
# "Green Dewitt Village" are riders' homes sitting in the agency-wide book. They
# are a misplacement, not a missing category, and they are listed instead.
#
# Dry run unless APPLY=1.

RESIDENTIAL = /\A\s*home\b|\bapts?\b|apartment|\bhouse\b|rv park|trailer park|mobile home|\bvillage\b/i

RULES = [
  ['Dialysis', /dialysis|davita|daviata|devita|fresenius|kidney|\brai\b/i],

  ['Senior Center', /\bsenior|\bsrs?\b\s*(ctr|center)|nursing home|nursing center|nursing rehab|
                     assisted living|retirement|adult day|\belder|activity cent/ix],

  ['Education', /school|element|jr\.?\s*high|junior high|\bhigh\b|\bhs\b|\bjh\b|\bbchs\b|\bbcjh\b|\bchs\b|
                 learning cent|academy|\bisd\b|college|universit|campus|head start|day\s?care|
                 petite|montessori|stadium/ix],

  ['Transit', /transit|greyhound|airport|bus stop|bus station|bus garage|\bdepot\b/i],

  ['Government & Social Services',
   /court|city hall|social security|\bdshs\b|\bdps\b|post office|library|police|sheriff|
    housing authority|food bank|salvation army|goodwill|veteran|workforce|work\s?shop|
    church|chapel|baptist|methodist|catholic|episcopal|lutheran|\bholy\b|ministr|kc hall|parish|
    community cent|animal shelter|helping hands|kitchen|civic|convention/ix],

  ['Employment', /employment|staffing|\bjobs?\b|\bplant\b|wire works|woodwork|enterprises|
                  manufact|industr|packing|caterpillar|inteplast|kaspar|saddles|\bmill\b/ix],

  ['Medical', /hospital|clinic|medical|medicine|\bhealth|physician|surgery|surgical|dental|dentist|
               orthope|cardio|oncolog|cancer|imaging|radiolog|pharmac|therapy|thepary|rehab|
               urgent care|vision|hearing|pediatric|wellness|care cent|\bdoctor|
               # Anchored: DR means Doctor only at the start of a name. Loose, it also
               # matches the street suffix, and "N Blue Herion DR" is a road.
               \Adr\.?\s+[a-z]|\bdr\.?\s+[a-z]{3,}\z|
               chiropract|hospice|bariatric|recovery|christus|optom|\blab\b|biomat|plasma/ix],

  ['Retail & Grocery',
   /walmart|wal-?\s?mart|h-?e-?b\b|kroger|kwik|circle k|speedy stop|dollar|grocery|market|mall|
    \bstore\b|\bshop\b|shopping|target|aldi|brookshire|furniture|\bbank\b|\bcash\b|at&t|honda|
    salon|barber|\bhair\b|beauty|nails|styl|kutting|sassy|boutique|
    restaurant|burger|chick|\bkfc\b|ihop|deli\b|pizza|taco|cafe|diner|grill|corral|grandys|
    sonic|subway|wendy|denny|drive-?in|donut|bakery|\bbbq\b|steak|jack in|whataburger|mcdonald|
    hotel|motel|\binn\b|la quinta|hilton|best west|
    \bgym\b|fitness|bowling|\blanes\b|theat|cinema|golf/ix],
].freeze

apply = ENV['APPLY'] == '1'
groups = AddressGroup.where(name: RULES.map(&:first)).index_by(&:name)
unknown = AddressGroup.find_by_name!(AddressGroup::UNKNOWN_TYPE)

rows = Address.where(deleted_at: nil, type: 'ProviderCommonAddress', address_group_id: unknown.id)
              .where.not(name: nil).reject { |a| a.name =~ /\A\s*\d/ }

residential, classified, unmatched = [], {}, []
rows.each do |a|
  if a.name =~ RESIDENTIAL then residential << a; next end
  hit = RULES.find { |_, re| a.name =~ re }
  hit ? classified[a.id] = groups[hit.first] : unmatched << a
end

puts(apply ? 'APPLYING' : 'DRY RUN -- nothing will change (set APPLY=1)')
puts
puts "on Needs Update, word-named : #{rows.size}"
puts "  newly classified          : #{classified.size}"
puts "  residential, left alone   : #{residential.size}"
puts "  still unmatched           : #{unmatched.size}"
puts
classified.values.group_by(&:name).sort_by { |_, v| -v.size }.each { |n, v| puts format('  %-30s %d', n, v.size) }

File.write(ENV['REPORT'] || '/var/www/ridepilot/tmp/reclassify-report.txt', begin
  s = +"NEWLY CLASSIFIED\n"
  classified.each { |id, g| s << format("  %-30s %s\n", g.name, Address.find(id).name) }
  s << "\nRESIDENTIAL -- customer addresses in the provider book, left on Needs Update\n"
  residential.each { |a| s << "  #{a.id}  #{a.name}  (#{a.city})\n" }
  s << "\nSTILL UNMATCHED\n"
  unmatched.each { |a| s << "  #{a.id}  #{a.name}\n" }
  s
end)

exit unless apply
ActiveRecord::Base.transaction do
  classified.group_by { |_, g| g.id }.each { |gid, pairs| Address.where(id: pairs.map(&:first)).update_all(address_group_id: gid) }
end
puts "\ndone."
