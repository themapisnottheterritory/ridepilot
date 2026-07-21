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
  
  NewAddressOption = { :label => "New Address", :id => 0 }

  scope :for_provider,    -> (provider) { where(:provider_id => provider.id) }
  scope :search_for_term, -> (term) { where("LOWER(name) LIKE '%' || :term || '%' OR LOWER(building_name) LIKE '%' || :term || '%' OR LOWER(address) LIKE '%' || :term || '%'",{:term => term}) }

  # compute RGeo geom 
  def self.compute_geom(lat, lon)
    RGeo::Geographic.spherical_factory(srid: 4326).point(lon.to_f, lat.to_f) if lat.present? && lon.present?
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
