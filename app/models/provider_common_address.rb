class ProviderCommonAddress < Address

  belongs_to :address_group

  validates :address_group_id, presence: true
  validates :name, presence: true

  scope :type_unknown, -> { where(address_group_id: nil) }

  scope :sort_by_name, -> { order("lower(name)") }

  #validates :provider, presence: true

  # GCRPC service-area bounding box. Shah has known geocode outliers (e.g. a
  # Goliad record that lands in Georgia); reject anything clearly outside the
  # region so bad coordinates don't get loaded. lat 27.5..30.3, lon -98.8..-95.5.
  SERVICE_AREA_LAT = (27.5..30.3)
  SERVICE_AREA_LON = (-98.8..-95.5)

  # Rider-residence placeholders that must NOT enter the provider book -- these
  # belong on the customer record as CustomerCommonAddress. Matches "Home",
  # "Home Urban/Rural", and "Home-<county>" (e.g. Home-Dewitt); does NOT match
  # real destinations like "Home Depot"/"HomeGoods".
  def self.placeholder_name?(name)
    n = name.to_s.strip.downcase
    n == "home" || n == "home urban" || n == "home rural" || n.match?(/\Ahome\s*-\s*\w+\z/)
  end

  # Load provider common addresses from a CSV. Columns (positional, as emitted
  # by the Shah extraction query):
  #   0 longitude  1 latitude  2 name  3 building_name  4 address  5 unit/address2
  #   6 city  7 state  8 zip  9 address_group  10 notes
  #
  # dry_run: true validates every row inside a rolled-back transaction and
  # reports counts without persisting anything or touching the provider's
  # upload flag.
  def self.load_addresses(filename, provider, dry_run: false)
    require 'csv'

    Rails.logger.info "Loading common addresses from '#{filename}'#{' (DRY RUN)' if dry_run}"
    Rails.logger.info "Starting at: #{Time.current}"

    counts = Hash.new(0)   # good, possible_existing, placeholder, out_of_bounds, bad_no_name, failed
    failures = []

    unless provider
      Rails.logger.info "Provider is nil..."
      return "Provider is nil -- nothing loaded"
    end

    provider.address_upload_flag.uploading! unless dry_run

    address_group_lookups = AddressGroup.pluck("lower(name)", :id).to_h
    default_address_group_id = AddressGroup.default_address_group.try(:id)

    ActiveRecord::Base.transaction do
      # Defect 3: Kernel#open no longer delegates to URI on Ruby 3+ (and is a
      # security smell); use File.open for local paths.
      File.open(filename) do |f|
        CSV.new(f, col_sep: ",", headers: true).each do |row|
          name  = row[2].to_s.strip
          city  = row[6]
          state = row[7]
          lon   = row[0].to_s.strip
          lat   = row[1].to_s.strip

          # Defect 2: join street (col 4) + unit (col 5) with a space instead of
          # concatenating into "123 Main StSuite 200"; tolerate a blank col 5.
          street = [row[4], row[5]].map { |x| x.to_s.strip }.reject(&:blank?).join(" ")

          address_group_id = address_group_lookups[row[9].to_s.downcase] || default_address_group_id

          # Part 4: skip blank-name rows (name is required) ...
          if name.blank?
            counts[:bad_no_name] += 1
            next
          end
          # ... and rider-residence placeholders (Home family).
          if placeholder_name?(name)
            counts[:placeholder] += 1
            next
          end

          # Part 3: reject geocode outliers outside the service area.
          if lat.present? && lon.present? && !(SERVICE_AREA_LAT.cover?(lat.to_f) && SERVICE_AREA_LON.cover?(lon.to_f))
            counts[:out_of_bounds] += 1
            failures << "out-of-bounds (#{lat},#{lon}): #{name}"
            next
          end

          # Defect 1: the dedup guard now includes the STREET ADDRESS. Without it,
          # distinct streets sharing a name+city collapsed into one row silently.
          if !address_group_id || ProviderCommonAddress.exists?([
              "address_group_id = ? AND provider_id = ? AND lower(name) = ? AND lower(address) = ? AND lower(city) = ? AND lower(state) = ?",
              address_group_id, provider.id, name.downcase, street.downcase, city.to_s.downcase, state.to_s.downcase])
            counts[:possible_existing] += 1
            next
          end

          begin
            ProviderCommonAddress.create!(
              provider: provider,
              the_geom: Address.compute_geom(row[1], row[0]),
              name: name,
              building_name: row[3],
              address: street,
              city: city,
              state: state,
              zip: row[8],
              address_group_id: address_group_id,
              notes: row[10]
            )
            counts[:good] += 1
          rescue => e
            # Defect 4: surface WHY a row failed instead of swallowing it.
            counts[:failed] += 1
            msg = "'#{name}' / '#{street}' / '#{city}': #{e.class}: #{e.message}"
            failures << msg
            Rails.logger.error "ProviderCommonAddress load failed -- #{msg}"
          end
        end
      end

      raise ActiveRecord::Rollback if dry_run
    end

    summary = "Common address #{'DRY RUN ' if dry_run}load: " \
              "loaded=#{counts[:good]}, possible_existing=#{counts[:possible_existing]}, " \
              "placeholder_skipped=#{counts[:placeholder]}, out_of_bounds=#{counts[:out_of_bounds]}, " \
              "blank_name=#{counts[:bad_no_name]}, failed=#{counts[:failed]}"
    Rails.logger.info summary
    failures.first(50).each { |m| Rails.logger.info "  - #{m}" } if failures.any?

    unless dry_run
      provider.address_upload_flag.uploaded!
      provider.address_upload_flag.last_upload_summary = summary
      provider.address_upload_flag.save
    end

    summary
  end
end
