require 'open-uri'

# Builds and canonicalizes the street dictionary.
#
# Two phases, deliberately separate:
#
#   collect     distinct street/city pairs out of the address book, with a
#               weight so common streets rank first. Cheap, no network.
#   canonicalize ask the geocoder what each street is really called, and store
#               that. Slow (one request per new street), so it is resumable and
#               only ever touches rows it has not already resolved.
#
# The canonicalize phase is not optional polish. Completing from our own street
# text measurably underperforms doing nothing -- local data disagrees with OSM
# about street types often enough to send the geocoder down the wrong path --
# whereas completing from the canonical name resolved every address it covered
# in testing. Entries that fail to canonicalize stay unresolved and are held
# back from suggestions rather than guessed at.
class StreetDictionaryBuilder
  NOMINATIM_URL = ENV['NOMINATIM_URL'].presence || 'http://10.0.0.18:8088'
  DEFAULT_STATE = ENV['NOMINATIM_FALLBACK_STATE'].presence || 'TX'

  # Be a good neighbour to the geocoder even though it is ours.
  REQUEST_PAUSE = 0.05

  attr_reader :stats

  def initialize(logger: Rails.logger, state: DEFAULT_STATE)
    @logger = logger
    @state  = state
    @stats  = Hash.new(0)
  end

  def run(limit: nil)
    collect
    canonicalize(limit: limit)
    stats
  end

  # Phase 1 -- distinct (street, city) out of the address book.
  def collect
    counts = Hash.new(0)

    Address.where.not(the_geom: nil)
           .where.not(address: [nil, ''])
           .where.not(city: [nil, ''])
           .pluck(:address, :city)
           .each do |address, city|
      _house, street = StreetDictionaryEntry.split_house_number(address)
      next if street.blank? || street.length < 3

      counts[[street.strip, city.strip]] += 1
    end

    counts.each do |(street, city), weight|
      entry = StreetDictionaryEntry.find_or_initialize_by(
        raw_street: street, city: city, state: @state
      )
      # A changed weight must not invalidate an existing canonical name.
      entry.weight = weight
      entry.save!
      @stats[entry.previously_new_record? ? :created : :refreshed] += 1
    end

    @stats[:collected] = counts.size
    log "collect: #{counts.size} distinct street/city pairs " \
        "(#{@stats[:created]} new, #{@stats[:refreshed]} existing)"
    @stats
  end

  # Phase 2 -- resolve each unresolved entry to OSM's name for it.
  def canonicalize(limit: nil)
    scope = StreetDictionaryEntry.unresolved.order(weight: :desc)
    scope = scope.limit(limit) if limit
    total = scope.count
    log "canonicalize: #{total} unresolved entries"

    # Deliberately not find_each: it forces batch ordering and would discard
    # the weight ordering, which is what makes a partial (LIMIT=) run resolve
    # the most-used streets first. The table is small enough to load.
    scope.to_a.each_with_index do |entry, i|
      road = lookup_road(entry.raw_street, entry.city)

      if road.present?
        entry.update!(street: road,
                      search_key: StreetDictionaryEntry.normalize(road),
                      resolved_at: Time.current)
        @stats[:resolved] += 1
      else
        @stats[:unresolved] += 1
      end

      log "  #{i + 1}/#{total} resolved=#{@stats[:resolved]}" if ((i + 1) % 250).zero?
      sleep REQUEST_PAUSE
    end

    log "canonicalize: #{@stats[:resolved]} resolved, #{@stats[:unresolved]} could not be matched"
    @stats
  end

  private

  # Two attempts: the street as we hold it, then with the last token dropped.
  # The second catches the case where our street type is simply wrong -- OSM
  # finds "Del Rio ___" even when it disagrees about "St".
  def lookup_road(street, city)
    [street, street.sub(/\s+\S+\z/, '')].uniq.each do |candidate|
      next if candidate.blank? || candidate.length < 3

      results = geocode(street: candidate, city: city, state: @state)
      road = results.dig(0, 'address', 'road')
      return road if road.present?
    end
    nil
  end

  def geocode(**params)
    query = { format: 'json', addressdetails: 1, countrycodes: 'us', limit: 1 }.merge(params)
    url   = "#{NOMINATIM_URL}/search?#{query.to_query}"

    ActiveSupport::JSON.decode(
      OpenURI.open_uri(url, open_timeout: 5, read_timeout: 10).read
    )
  rescue StandardError => e
    @stats[:errors] += 1
    log "  lookup failed (#{params.inspect}): #{e.class}: #{e.message}"
    []
  end

  def log(message)
    @logger.info "[street_dictionary] #{message}"
  end
end
