class StreetDictionaryEntry < ApplicationRecord
  # Prefix-completable street names drawn from our own address book. See the
  # migration for why this exists and why `street` (OSM's name) rather than
  # `raw_street` (ours) is what gets suggested.

  scope :resolved, -> { where.not(street: nil) }
  scope :unresolved, -> { where(street: nil) }

  DIRECTIONALS = {
    'n' => 'north', 's' => 'south', 'e' => 'east', 'w' => 'west',
    'ne' => 'northeast', 'nw' => 'northwest',
    'se' => 'southeast', 'sw' => 'southwest'
  }.freeze

  STREET_TYPES = {
    'st' => 'street', 'str' => 'street', 'ave' => 'avenue', 'av' => 'avenue',
    'rd' => 'road', 'dr' => 'drive', 'ln' => 'lane', 'blvd' => 'boulevard',
    'cir' => 'circle', 'ct' => 'court', 'trl' => 'trail', 'pl' => 'place',
    'hwy' => 'highway', 'pkwy' => 'parkway', 'expy' => 'expressway',
    'ter' => 'terrace'
  }.freeze

  LEADING_HOUSE_NUMBER = /\A\s*(\d+[A-Za-z]?)\s+/
  # Keyword-introduced unit ("APT 3", "Ste B") ...
  UNIT_KEYWORD = /\b(?:apt|apartment|unit|ste|suite|lot|trlr|rm|room|bldg|#)\b.*\z/i
  # ... and the bare trailing codes that carry no keyword at all ("Leary Ln NO6",
  # "Village Dr 94"). Left attached, these strings do not geocode.
  UNIT_TAIL = /[\s,]+(?:no\.?\s*\d+\S*|\d+[A-Za-z]?|[A-Za-z]?-?\d+[A-Za-z]?)\z/i

  class << self
    # Splits "1404 E Virginia Ave Apt 2" into ["1404", "E Virginia Ave"].
    # Returns a nil house number when the string does not start with one.
    def split_house_number(text)
      s = text.to_s.strip
      m = LEADING_HOUSE_NUMBER.match(s)
      house = m && m[1]
      s = s[m.end(0)..] if m
      [house, strip_unit(s)]
    end

    def strip_unit(text)
      s = text.to_s.sub(UNIT_KEYWORD, '').strip.sub(/[,.\-\s]+\z/, '')
      # Repeat: "800 Ave F J-138" sheds one token at a time.
      3.times do
        stripped = s.sub(UNIT_TAIL, '').strip.sub(/[,.\-\s]+\z/, '')
        break if stripped == s || stripped.length < 3
        s = stripped
      end
      s
    end

    # Lowercase, depunctuate, and expand abbreviations so that what the user
    # types and what we stored normalize to the same string -- "E Vir" becomes
    # "east vir", which prefix-matches the stored "east virginia avenue".
    def normalize(text)
      text.to_s.downcase.gsub(/[^\w\s]/, ' ').split.map { |w|
        DIRECTIONALS[w] || STREET_TYPES[w] || w
      }.join(' ')
    end

    # Streets whose canonical name begins with (or contains) the typed
    # fragment, most-used first. Prefix hits rank above substring hits so that
    # "main" offers "Main Street" before "West Main Street".
    def complete(fragment, limit: 3)
      # Guard on what was typed, not on its expansion: a lone "E" normalizes to
      # "east" and would otherwise match every east-side street in the county.
      return none if fragment.to_s.strip.length < 2

      key = normalize(fragment)
      return none if key.blank?

      escaped = sanitize_sql_like(key)
      resolved
        .where('search_key LIKE :prefix OR search_key LIKE :anywhere',
               prefix: "#{escaped}%", anywhere: "%#{escaped}%")
        .order(Arel.sql(
          ActiveRecord::Base.sanitize_sql_array(
            ['CASE WHEN search_key LIKE ? THEN 0 ELSE 1 END, weight DESC, street ASC',
             "#{escaped}%"]
          )
        ))
        .limit(limit)
    end
  end
end
