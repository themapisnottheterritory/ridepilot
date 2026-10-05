class Address < ApplicationRecord
  acts_as_paranoid # soft delete
  
  belongs_to :provider, -> { with_deleted }, optional: true

  belongs_to :customer, -> { with_deleted }, inverse_of: :addresses, optional: true

  has_one :driver

  belongs_to :trip_purpose, -> { with_deleted }, optional: true
  delegate :name, to: :trip_purpose, prefix: :trip_purpose, allow_nil: true
  
  has_many :trips_from, :class_name => "Trip", :foreign_key => :pickup_address_id
  has_many :trips_to, :class_name => "Trip", :foreign_key => :dropoff_address_id

  normalize_attribute :name, :with=> [:squish, :titleize]
  normalize_attribute :building_name, :with=> [:squish, :titleize]
  normalize_attribute :address, :with=> [:squish, :titleize]
  normalize_attribute :city, :with=> [:squish, :titleize]

  validates :address, :length => { :minimum => 5, :unless => :geocoded? }
  validates :city,    :length => { :minimum => 2, :unless => :geocoded? }
  validates :state,   :length => { :is => 2, :unless => :geocoded? }
  validates :zip,     :length => { :is => 5, :if => lambda { |a| a.zip.present? } }
  validate :address_presented # must be put below above validations (address/city/state/zip)
  validate :valid_phone_number
  
  before_validation :compute_in_district

  has_paper_trail

  # A trip address typed in full ("2401 Patterson Drive") that is a saved place
  # takes the saved place's name, so the trip shows "Victoria Heart & Vascular"
  # instead of a street only callers can't place (PlaceNaming, 2026-10-05).
  # Never stops an address from saving.
  before_create :take_saved_place_name, if: -> { name.blank? && %w[TempAddress CustomerCommonAddress].include?(type) }

  def take_saved_place_name
    self.name = PlaceNaming.saved_name_for(self) || name
  rescue StandardError => e
    Rails.logger.warn "take_saved_place_name: #{e.class}: #{e.message}"
  ensure
    return true
  end
  
  NewAddressOption = { :label => "New Address", :id => 0 }

  scope :for_provider,    -> (provider) { where(:provider_id => provider.id) }
  scope :search_for_term, -> (term) { where("LOWER(name) LIKE '%' || :term || '%' OR LOWER(building_name) LIKE '%' || :term || '%' OR LOWER(address) LIKE '%' || :term || '%'",{:term => term}) }

  # compute RGeo geom 
  # Where GCRPC's riders are (Utility#get_provider_bounds, 2026): every real
  # pin is inside this box.
  SERVICE_AREA = { min_lat: 27.5, max_lat: 30.6, min_lon: -98.9, max_lon: -95.0 }.freeze

  def self.compute_geom(lat, lon)
    return nil unless lat.present? && lon.present?
    lat = coordinate(lat, :lat)
    lon = coordinate(lon, :lon)
    return nil unless lat && lon
    RGeo::Geographic.spherical_factory(srid: 4326).point(lon, lat)
  end

  # Since 2026-09-30 the address dialog's longitude box has arrived as bare
  # digits ("9765114006172236" for -97.65114006172236), sign and decimal point
  # gone; the point factory wrapped that to a whole-number longitude (-84, 114,
  # -174 ...) half a world away, and a 2-mile trip measured 313 or 648 miles.
  # Cause in the browser not yet found. A digits-only value is put back the way
  # it must have been (two-digit degrees, west of Greenwich for longitude) only
  # if that lands in the service area; anything else impossible gives no pin,
  # so the save says the address isn't on the map instead of placing it abroad.
  def self.coordinate(value, axis)
    text = value.to_s.strip
    if text.match?(/\A\d{6,}\z/)
      fixed = (axis == :lon ? -1 : 1) * "#{text[0, 2]}.#{text[2..]}".to_f
      lo, hi = axis == :lon ? SERVICE_AREA.values_at(:min_lon, :max_lon) : SERVICE_AREA.values_at(:min_lat, :max_lat)
      return nil unless fixed.between?(lo, hi)
      Rails.logger.warn("[address] repaired a digits-only #{axis} #{text} -> #{fixed}")
      return fixed
    end
    number = Float(text, exception: false)
    return nil unless number
    limit = axis == :lon ? 180 : 90
    number.abs <= limit ? number : nil
  end

  def as_json
    addr_data = self.attributes
    addr_data[:label] = self.address_text

    addr_data[:coded_by_lat_lng] = self.coded_by_lat_lng?
    addr_data[:latitude] = self.latitude
    addr_data[:longitude] = self.longitude

    addr_data
  end

  def trips
    trips_from + trips_to
  end
  
  def replace_with!(address_id)
    return false unless address_id.present? && self.class.exists?(address_id)
    
    self.trips_from.update_all pickup_address_id: address_id
    
    self.trips_to.update_all dropoff_address_id: address_id
    
    self.destroy
    self.class.find address_id
  end
  
  # deprecated
  def compute_in_district
    if the_geom and in_district.nil?
      #in_district = Region.count(:conditions => ["is_primary = 't' and st_contains(the_geom, ?)", the_geom]) > 0
      true # avoid returning false while doing before_validation
    end 
    
  end

  def latitude
    the_geom.y if the_geom
  end

  def longitude
    the_geom.x if the_geom
  end

  def latitude=(y)
    the_geom.y = y if the_geom
  end

  def longitude=(x)
    the_geom.x = x if the_geom
  end

  def geocoded?
    !the_geom.nil?
  end

  def text
    unless coded_by_lat_lng?
      if name.to_s.size > 0
        first_line = name + "\n"
      else
        first_line = ''
      end

      ("%s %s \n%s, %s %s" % [first_line, address, city, state, zip]).strip 
    else
      lat_lng_text
    end
  end

  def one_line_text
    unless coded_by_lat_lng?
      regular_text = if name
        ("%s (%s %s, %s %s)" % [name, address, city, state, zip]).strip 
      else
        ("%s %s, %s %s" % [address, city, state, zip]).strip
      end
    else
      lat_lng_text
    end
  end

  def address_text
    unless coded_by_lat_lng?
      (
        (address.blank? ? '' : address + ", " ) +
        (city.blank? ?  '' : city + ", " ) +
        ("%s %s" % [state, zip])
      ).strip 
    else
      lat_lng_text
    end
  end

  def lat_lng_text
    "(#{latitude}, #{longitude})" if geocoded?
  end

  def same_geom_as?(a_address)
    lat_lng_text.to_s == a_address.try(:lat_lng_text).to_s
  end

  def same_lat_lng?(lat, lng)
    latitude.to_s == lat.to_s && longitude.to_s == lng.to_s 
  end

  def coded_by_lat_lng?
    [address, city, state, zip].compact.join("").blank? && geocoded?
  end

  def json
    {
      :label => text, 
      :id => id, 
      :name => name,
      :building_name => building_name,
      :address => address,
      :city => city,
      :state => state,
      :zip => zip,
      :in_district => in_district,
      :phone_number => phone_number,
      :lat => latitude,
      :lon => longitude,
      :default_trip_purpose => trip_purpose_name,
      :trip_purpose_id => trip_purpose.try(:id),
      :notes => notes
    }
  end

  def address_presented
    errors.add(:base, TranslationEngine.translate_text(:address_required)) unless address_text.present?
  end

  private

  def valid_phone_number
    util = Utility.new
    if phone_number.present?
      errors.add(:phone_number, 'is invalid') unless util.phone_number_valid?(phone_number) 
    end
  end

end
