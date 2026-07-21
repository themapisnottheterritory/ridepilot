require 'net/http'
require 'json'

LOG_FILE = '/var/www/ridepilot/log/geocoding.log'

def log(msg)
  line = "#{Time.current}: #{msg}"
  puts line
  File.open(LOG_FILE, 'a') { |f| f.puts(line) }
end

def clean_address(raw)
  return nil if raw.blank?
  a = raw.dup
  a.gsub!(/\b(suite|ste|apt|unit|#|no\.|lot|sp|spc|trlr|bldg|room|rm)\s*\.?\s*\w+/i, '')
  a.gsub!(/\bp\.?o\.?\s*box\s*\d*/i, '')
  a.gsub!(/\bCR\s+(\d+)/i, 'County Road \1')
  a.gsub!(/\bFM\s+(\d+)/i, 'Farm to Market Road \1')
  a.gsub!(/\bHwy\s+(\d+)/i, 'Highway \1')
  a.gsub!(/\bN\.\s/, 'North ')
  a.gsub!(/\bS\.\s/, 'South ')
  a.gsub!(/\bE\.\s/, 'East ')
  a.gsub!(/\bW\.\s/, 'West ')
  a.gsub!(/\bSt\b/, 'Street')
  a.gsub!(/\bDr\b/, 'Drive')
  a.gsub!(/\s+/, ' ')
  a.strip
end

def geocode_one(query)
  return nil if query.blank?
  url = 'https://nominatim.openstreetmap.org/search?q=' + URI.encode_www_form_component(query) + '&format=json&limit=1&countrycodes=us'
  uri = URI(url)
  req = Net::HTTP::Get.new(uri)
  req['User-Agent'] = 'VictoriaTransit-RidePilot/1.0 (paratransit geocoding)'
  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 10) { |http| http.request(req) }
  result = JSON.parse(response.body)
  if result.any?
    return [result[0]['lat'].to_f, result[0]['lon'].to_f]
  end
  nil
rescue => e
  log("  ERROR: #{e.message}")
  nil
end

total = Address.where(the_geom: nil).count
log("=== BATCH GEOCODING v2 START ===")
log("Already geocoded: #{Address.where.not(the_geom: nil).count}")
log("Need geocoding: #{total}")

success = 0
failed = 0
skipped = 0
batch_num = 0

Address.where(the_geom: nil).find_in_batches(batch_size: 100) do |batch|
  batch_num += 1
  log("--- Batch #{batch_num} (#{success + failed + skipped}/#{total}) ---")
  batch.each do |addr|
    raw = addr.address.to_s.strip
    city = addr.city.to_s.strip
    state = addr.state.to_s.strip
    zip = addr.zip.to_s.strip

    if raw.blank? || city.blank?
      skipped += 1
      next
    end

    if raw =~ /\bp\.?o\.?\s*box/i
      skipped += 1
      next
    end

    cleaned = clean_address(raw)
    query = [cleaned, city, state, zip].reject(&:blank?).join(', ')
    coords = geocode_one(query)

    if coords.nil? && cleaned != raw
      sleep 1.1
      query2 = [raw, city, state, zip].reject(&:blank?).join(', ')
      coords = geocode_one(query2)
    end

    if coords.nil?
      sleep 1.1
      query3 = [city, state, zip].reject(&:blank?).join(', ')
      coords = geocode_one(query3)
      if coords
        log("  CITY-ONLY: #{addr.id} - #{raw}, #{city}")
      end
    end

    if coords
      begin
        addr.the_geom = Address.compute_geom(coords[0], coords[1])
        addr.save(validate: false)
        success += 1
      rescue => e
        log("  SAVE ERROR #{addr.id}: #{e.message}")
        failed += 1
      end
    else
      failed += 1
      log("  NO RESULT: #{addr.id} - #{raw}, #{city}, #{state} #{zip}")
    end
    sleep 1.1
  end
  log("Progress: #{success} ok, #{failed} fail, #{skipped} skip / #{total}")
end

log("=== BATCH GEOCODING v2 COMPLETE ===")
log("Success: #{success}, Failed: #{failed}, Skipped: #{skipped}")
log("Total geocoded: #{Address.where.not(the_geom: nil).count}")
