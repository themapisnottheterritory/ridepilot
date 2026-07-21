require 'net/http'
require 'json'

LOG_FILE = '/var/www/ridepilot/log/geocoding.log'

def log(msg)
  line = "#{Time.current}: #{msg}"
  puts line
  File.open(LOG_FILE, 'a') { |f| f.puts(line) }
end

def geocode_one(addr)
  query = [addr.address, addr.city, addr.state, addr.zip].compact.reject(&:blank?).join(', ')
  return nil if query.strip.blank?
  url = 'https://nominatim.openstreetmap.org/search?q=' + URI.encode_www_form_component(query) + '&format=json&limit=1&countrycodes=us'
  uri = URI(url)
  req = Net::HTTP::Get.new(uri)
  req['User-Agent'] = 'VictoriaTransit-RidePilot/1.0 (paratransit geocoding)'
  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 10) { |http| http.request(req) }
  result = JSON.parse(response.body)
  if result.any?
    lat = result[0]['lat'].to_f
    lon = result[0]['lon'].to_f
    return [lat, lon]
  end
  nil
rescue => e
  log("  ERROR on address #{addr.id}: #{e.message}")
  nil
end

total = Address.where(the_geom: nil).count
already_done = Address.where.not(the_geom: nil).count
log("=== BATCH GEOCODING START ===")
log("Total addresses: #{Address.count}")
log("Already geocoded: #{already_done}")
log("Need geocoding: #{total}")

success = 0
failed = 0
skipped = 0
batch_num = 0

Address.where(the_geom: nil).find_in_batches(batch_size: 100) do |batch|
  batch_num += 1
  log("--- Batch #{batch_num} (#{success + failed + skipped}/#{total}) ---")
  batch.each do |addr|
    query_text = [addr.address, addr.city, addr.state, addr.zip].compact.reject(&:blank?).join(', ')
    if query_text.strip.blank?
      skipped += 1
      next
    end
    coords = geocode_one(addr)
    if coords
      lat, lon = coords
      begin
        addr.the_geom = Address.compute_geom(lat, lon)
        addr.save(validate: false)
        success += 1
      rescue => e
        log("  SAVE ERROR #{addr.id}: #{e.message}")
        failed += 1
      end
    else
      failed += 1
      log("  NO RESULT: #{addr.id} - #{query_text}")
    end
    sleep 1.1
  end
  log("Progress: #{success} success, #{failed} failed, #{skipped} skipped out of #{total}")
end

log("=== BATCH GEOCODING COMPLETE ===")
log("Success: #{success}")
log("Failed: #{failed}")
log("Skipped: #{skipped}")
log("Total geocoded now: #{Address.where.not(the_geom: nil).count}")
