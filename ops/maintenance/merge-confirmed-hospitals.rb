# Two merges confirmed by hand, on buildings a person knows.
#
#   Citizens Medical Center (Edna)   -> Citizens Hospital, 2701 Hospital DR
#   Cuero Hospital                   -> Cuero Community Hospital, 2550 Esplanade
#
# Both fell out of the automatic HIGH tier once category words stopped counting
# as evidence: "Cuero Hospital" and "Cuero Community Hospital" share only CUERO
# and HOSPITAL, and neither is distinctive here. That was the rule working --
# it declined to guess, and a human answered instead.
#
# Deliberately NOT merged, same addresses, different tenants:
#   Chen/Janson        2701 Hospital DR   -- a practice inside Citizens, not Citizens
#   New Horizons - Ykm 1200 Carl Ramert   -- a separate service in the hospital building

MERGES = { 106837 => 106421, 108477 => 106342 }.freeze
FKS = [['trips','pickup_address_id'],['trips','dropoff_address_id'],
       ['repeating_trips','pickup_address_id'],['repeating_trips','dropoff_address_id'],
       ['itineraries','address_id'],['repeating_itineraries','address_id']].freeze

apply = ENV['APPLY'] == '1'
puts(apply ? 'APPLYING' : 'DRY RUN (set APPLY=1)')
MERGES.each do |from, to|
  f = Address.find(from); t = Address.find(to)
  puts "  #{from} #{f.name} (#{f.city}) -> #{to} #{t.name} (#{t.city})"
end
exit unless apply

moved = 0
ActiveRecord::Base.transaction do
  MERGES.each do |from, to|
    FKS.each { |tb,c| moved += ActiveRecord::Base.connection.execute("UPDATE #{tb} SET #{c}=#{to} WHERE #{c}=#{from}").cmd_tuples }
    Address.find(from).destroy
  end
end
puts "\ndone. #{MERGES.size} merged, #{moved} references repointed"
puts "provider addresses live: #{Address.where(deleted_at: nil, type: 'ProviderCommonAddress').count}"
