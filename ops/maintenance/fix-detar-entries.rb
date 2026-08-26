# Tidy the DeTar entries.
#
# Nine real facilities, five rider-town copies the general dedupe missed because
# the key differed trivially -- a ST suffix, "Health" against "Healthcare" -- and
# one wrong ZIP. Detar North's 77968 is Inez; the address is confirmed as
# 101 Medical Dr, Victoria, TX 77904, and its coordinates were already right.
#
# The Plaza towers at 601 and 605, and the Health Center and Rehab Center that
# share 4204 N Laurent, stay separate: same building, different clinics, and a
# dispatcher choosing between them is choosing correctly.

MERGES = { 108343 => 106511, 107574 => 107520, 106404 => 106458,
           107053 => 106458, 108850 => 109083 }.freeze
FKS = [['trips','pickup_address_id'], ['trips','dropoff_address_id'],
       ['repeating_trips','pickup_address_id'], ['repeating_trips','dropoff_address_id'],
       ['itineraries','address_id'], ['repeating_itineraries','address_id']].freeze
MEDICAL = [109051, 106994, 107545, 106877].freeze

apply = ENV['APPLY'] == '1'
med = AddressGroup.find_by_name!('Medical')

puts(apply ? 'APPLYING' : 'DRY RUN (set APPLY=1)')
MERGES.each do |from, to|
  f = Address.find(from); t = Address.find(to)
  puts "  merge #{from} #{f.name} (#{f.city}) -> #{to} #{t.name} (#{t.city})"
end
puts "  Detar North 106994: zip 77968 -> 77904"
MEDICAL.each { |id| puts "  categorise #{id} #{Address.find(id).name} -> Medical" }

exit unless apply

ActiveRecord::Base.transaction do
  MERGES.each do |from, to|
    FKS.each { |tbl, col| ActiveRecord::Base.connection.execute("UPDATE #{tbl} SET #{col}=#{to} WHERE #{col}=#{from}") }
    Address.find(from).destroy
  end
  Address.where(id: 106994).update_all(zip: '77904', updated_at: Time.current)
  Address.where(id: MEDICAL).update_all(address_group_id: med.id, updated_at: Time.current)
end
puts "\ndone."
