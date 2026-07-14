class ProviderCommonAddress < Address
  
  belongs_to :address_group

  validates :address_group_id, presence: true
  validates :name, presence: true

  scope :type_unknown, -> { where(address_group_id: nil) }

  scope :sort_by_name, -> { order("lower(name)") }

  #validates :provider, presence: true

  def self.load_addresses(filename, provider) 
    require 'csv'
    require 'open-uri'
    alert_msgs = []
    Rails.logger.info "Loading common address from file '#{filename}'"
    Rails.logger.info "Starting at: #{Time.current}"

    count_good = 0
    count_bad = 0
    count_failed = 0
    count_possible_existing = 0

    if !provider
      Rails.logger.info "Provider is nil..."
    else
      provider.address_upload_flag.uploading!

      address_group_lookups = AddressGroup.pluck("lower(name)", :id).to_h
      default_address_group_id = AddressGroup.default_address_group.try(:id)

      open(filename) do |f|
        CSV.new(f, col_sep: ",", headers: true).each do |row|
          address_name = row[2]
          address_city = row[6]
          address_state = row[7]
          address_group_id = address_group_lookups[row[9].to_s.downcase] || default_address_group_id
          #If we have already created this common address, don't create it again.
          if !address_group_id || ProviderCommonAddress.exists?(["address_group_id = ? and provider_id = ? and lower(name) = ? and lower(city) = ? and lower(state) = ?", address_group_id, provider.try(:id), address_name.try(:downcase), address_city.try(:downcase), address_state.try(:downcase)])
            #Rails.logger.info "Possible duplicate: #{row}"
            count_possible_existing += 1
            next
          end
          begin
            if address_name
              p = ProviderCommonAddress.create!({
                provider: provider,
                the_geom: Address.compute_geom(row[1], row[0]),
                name: address_name,
                building_name: row[3],
                address: row[4].to_s + row[5].to_s,
                city: address_city,
                state: address_state,
                zip: row[8],
                address_group_id: address_group_id,
                notes: row[10]
              })
              count_good += 1
            else
              count_bad += 1
            end
          rescue Exception => e
            #Rails.logger.info "Failed to save: #{e.message} for #{p.ai}"
            count_failed += 1
          end
        end
      end
    end

    Rails.logger.info "Common address loading finished"
    provider.address_upload_flag.uploaded!

    sub_pairs = {
      count_good: count_good,
      count_failed: count_failed,
      count_bad: count_bad,
      count_possible_existing: count_possible_existing
    }

    summary_info = TranslationEngine.translate_text(:common_address_upload_summary) % sub_pairs
    provider.address_upload_flag.last_upload_summary = summary_info
    provider.address_upload_flag.save

    Rails.logger.info summary_info
    summary_info
  end
end