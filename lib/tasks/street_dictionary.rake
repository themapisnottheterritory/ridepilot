namespace :street_dictionary do
  desc 'Rebuild the street dictionary and canonicalize new entries against the geocoder'
  task build: :environment do
    limit = ENV['LIMIT'].presence&.to_i
    stats = StreetDictionaryBuilder.new(logger: Logger.new($stdout)).run(limit: limit)
    puts stats.inspect
  end

  desc 'Collect distinct streets only; no geocoder traffic'
  task collect: :environment do
    puts StreetDictionaryBuilder.new(logger: Logger.new($stdout)).collect.inspect
  end

  desc 'Canonicalize unresolved entries (LIMIT=n to work through it in batches)'
  task canonicalize: :environment do
    limit = ENV['LIMIT'].presence&.to_i
    puts StreetDictionaryBuilder.new(logger: Logger.new($stdout)).canonicalize(limit: limit).inspect
  end

  desc 'Coverage summary'
  task status: :environment do
    total      = StreetDictionaryEntry.count
    resolved   = StreetDictionaryEntry.resolved.count
    unresolved = total - resolved
    addresses  = StreetDictionaryEntry.sum(:weight)
    covered    = StreetDictionaryEntry.resolved.sum(:weight)

    puts "street dictionary"
    puts "  entries          : #{total}"
    puts "  canonicalized    : #{resolved}#{total.positive? ? " (#{100 * resolved / total}%)" : ''}"
    puts "  unresolved       : #{unresolved}"
    puts "  addresses covered: #{covered}/#{addresses}" \
         "#{addresses.positive? ? " (#{100 * covered / addresses}%)" : ''}"
  end

  desc 'Streets the geocoder could not match -- a data-quality worklist (CSV=path to write a file)'
  task unresolved: :environment do
    rows = StreetDictionaryEntry.unresolved.order(weight: :desc)
                                .pluck(:raw_street, :city, :weight)

    if (path = ENV['CSV'].presence)
      require 'csv'
      CSV.open(path, 'w') do |csv|
        csv << %w[street city addresses_affected]
        rows.each { |r| csv << r }
      end
      puts "wrote #{rows.size} rows to #{path}"
    else
      puts format('%-44s %-18s %s', 'STREET', 'CITY', 'ADDRESSES')
      rows.first(50).each { |street, city, weight| puts format('%-44s %-18s %d', street, city, weight) }
      puts "... #{rows.size - 50} more (re-run with CSV=/path/to/file.csv)" if rows.size > 50
    end
  end
end
