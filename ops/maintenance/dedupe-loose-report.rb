# Candidate merges under a LOOSER key than the first dedupe pass.
#
# The strict pass keyed on name+address and so missed the same place written two
# ways: "Cuero Community Hospital, 2550 Esplanade" against "Cuero Hospital,
# 2550 N Esplanade ST", or "Memorial Medical Center, 815 N Virginia ST" against
# "Memorial Medical Center- 815, 815 N Virginia". Street suffixes, directionals
# and punctuation are normalised away here so those meet.
#
# Matching on address ALONE is what makes this delicate: the same street number
# exists in every town, so clusters are ranked rather than merged, and nothing is
# applied. Report only.
#
#   HIGH    one name contains the other, or they share a distinctive word --
#           the same place spelled two ways
#   MEDIUM  names differ but every row sits at one address and at most one is
#           geocoded; probably one place, worth an eye
#   REVIEW  a member is named by its own street address, or the names are
#           unrelated. "1310 E Broadway" is a different building in every town
#           and these must not be merged blind.

SUFFIX = /\b(ST|STREET|DR|DRIVE|AVE|AVENUE|RD|ROAD|BLVD|BOULEVARD|LN|LANE|CT|COURT|
             HWY|HIGHWAY|PKWY|CIR|TRL|WAY|PL|SUITE|STE|APT|UNIT|NO|N|S|E|W)\b/x
# Category words are not evidence. Two tenants at one address both being a
# dialysis unit says nothing about their being the same unit -- 1105 E Broadway
# holds a Davita and a Lakeview -- so only a distinctive word counts as a match.
STOP = %w[THE AND OF CENTER CENTRE CENTER CTR CLINIC INC LLC CO
          DIALYSIS NURSING HOSPITAL MEDICAL HEALTH HEALTHCARE CARE REHAB
          SCHOOL COLLEGE SENIOR SENIORS CITIZENS ADULT DAYCARE HOME HOMES
          STORE MARKET PHARMACY OFFICE BUILDING PLAZA TOWER APARTMENTS
          SERVICES SERVICE ASSOCIATION ASSOC CENTERS EAST WEST NORTH SOUTH
          VICTORIA CUERO YOAKUM GOLIAD EDNA GONZALES SHINER GANADO INEZ
          BLOOMINGTON TELFERNER PLACEDO NORDHEIM YORKTOWN HALLETTSVILLE
          LAVACA CALHOUN JACKSON DEWITT MATAGORDA PALACIOS LOLITA SEADRIFT].freeze

def akey(s) = s.to_s.upcase.gsub(/[^A-Z0-9 ]/, ' ').gsub(SUFFIX, ' ').gsub(/\s+/, '')
def words(s) = s.to_s.upcase.scan(/[A-Z]{4,}/).reject { |w| STOP.include?(w) }
def streetish?(a) = a.name.to_s =~ /\A\s*\d/

FKS = [['trips','pickup_address_id'],['trips','dropoff_address_id'],
       ['repeating_trips','pickup_address_id'],['repeating_trips','dropoff_address_id'],
       ['itineraries','address_id'],['repeating_itineraries','address_id']].freeze
def refs(id)
  FKS.sum { |t,c| ActiveRecord::Base.connection.select_value("SELECT count(*) FROM #{t} WHERE #{c}=#{id.to_i}").to_i }
end

rows = Address.where(deleted_at: nil, type: 'ProviderCommonAddress').to_a
clusters = rows.group_by { |a| akey(a.address) }.select { |k, v| !k.empty? && v.size > 1 }

# Decided per ROW against the keeper, not per cluster. A cluster keyed only on
# street address can hold two unrelated tenants -- 111 E Alexander carries both
# the Alexander Adult Activity Center and a Davita clinic -- and judging the
# cluster as a whole let one matching pair drag the stranger in with it.
tiers = Hash.new { |h,k| h[k] = [] }
clusters.each do |_, members|
  keeper = members.min_by { |a| [a.the_geom ? 0 : 1, -refs(a.id), a.id] }
  kn = keeper.name.to_s.upcase.gsub(/[^A-Z0-9]/,'')
  kw = words(keeper.name)
  members.reject { |m| m == keeper }.each do |m|
    mn = m.name.to_s.upcase.gsub(/[^A-Z0-9]/,'')
    tier = if streetish?(m) || streetish?(keeper)          then :REVIEW
           elsif kn.include?(mn) || mn.include?(kn)        then :HIGH
           elsif (kw & words(m.name)).any?                 then :HIGH
           elsif m.the_geom.nil? && keeper.the_geom        then :MEDIUM
           else :REVIEW end
    tiers[tier] << [keeper, m]
  end
end

out = ENV['REPORT'] || '/var/www/ridepilot/tmp/loose-merge-candidates.txt'
File.open(out, 'w') do |f|
  [:HIGH, :MEDIUM, :REVIEW].each do |tier|
    f.puts "#{'='*74}\n#{tier}  --  #{tiers[tier].size} merges\n#{'='*74}"
    tiers[tier].sort_by { |k, m| k.id }.each do |keeper, m|
      f.puts format('  KEEP %-7d %-30s %-24s %-13s %-6s %-3s refs=%d',
                    keeper.id, keeper.name.to_s[0,30], keeper.address.to_s[0,24],
                    keeper.city.to_s[0,13], keeper.zip, keeper.the_geom ? 'geo' : '', refs(keeper.id))
      f.puts format('  drop %-7d %-30s %-24s %-13s %-6s %-3s refs=%d',
                    m.id, m.name.to_s[0,30], m.address.to_s[0,24],
                    m.city.to_s[0,13], m.zip, m.the_geom ? 'geo' : '', refs(m.id))
      f.puts
    end
  end
end

# APPLY=HIGH (or MEDIUM) merges exactly the tier the report just listed, using
# the same decisions -- the report and the action cannot drift apart because
# they are the same pass.
if (tier = ENV['APPLY'])
  chosen = tiers[tier.to_sym]
  abort "unknown tier #{tier}" if chosen.nil? || chosen.empty?
  moved = 0
  ActiveRecord::Base.transaction do
    chosen.each do |keeper, m|
      FKS.each do |tbl, col|
        moved += ActiveRecord::Base.connection.execute(
          "UPDATE #{tbl} SET #{col}=#{keeper.id} WHERE #{col}=#{m.id}").cmd_tuples
      end
      m.destroy
    end
  end
  puts "APPLIED #{tier}: #{chosen.size} merges, #{moved} references repointed"
  puts "provider addresses live: #{Address.where(deleted_at: nil, type: 'ProviderCommonAddress').count}"
  exit
end

puts "REPORT ONLY -- nothing changed."
[:HIGH, :MEDIUM, :REVIEW].each { |t| puts format('  %-7s %3d merges (%d carry trips)', t, tiers[t].size, tiers[t].count { |_, m| refs(m.id) > 0 }) }
puts "\nfull detail: #{out}"
