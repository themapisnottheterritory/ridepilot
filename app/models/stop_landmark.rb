# A recognisable place near a fixed-route stop, for Next Bus: "the stop by
# the Whataburger". Seeded from the map (source "map", StopLandmark.seed_from);
# CSRs add their own from the Next Bus page (source "staff") and hide bad ones
# (hidden, kept so a re-seed doesn't bring them back).
class StopLandmark < ApplicationRecord
  belongs_to :created_by, class_name: "User", optional: true

  validates :stop_id, :name, presence: true
  validates :name, length: { maximum: 80 }
  validates :name, uniqueness: { scope: :stop_id, case_sensitive: false }

  scope :shown, -> { where(hidden: false) }

  # Map features that aren't landmarks to a rider: historic markers,
  # parking lots, helipads and the like.
  SKIP_KINDS = %w[memorial parking parking_space parking_entrance helipad bench waste_basket shelter grave_yard
                  bicycle_parking toilets drinking_water vending_machine atm post_box telephone yes].freeze
  # what a rider is likely to recognise first
  KIND_ORDER = %w[supermarket fast_food fuel pharmacy hospital school place_of_worship library restaurant convenience
                  bank cinema mall department_store hotel fire_station police clinic doctors].freeze
  PER_STOP = 3

  # Best first: staff-added, then brands (H-E-B, Whataburger), then the kinds
  # riders recognise, then nearest.
  def rank
    [source == "staff" ? 0 : 1, brand ? 0 : 1, KIND_ORDER.index(kind) || KIND_ORDER.size, meters || 9999]
  end

  def self.for_stops(stop_ids)
    shown.where(stop_id: stop_ids).group_by(&:stop_id).transform_values { |ls| ls.sort_by(&:rank).first(PER_STOP) }
  end

  # rows: [stop_id, class, type, name, brand, lat, lon, metres] from the map
  # database (ops/next-bus-landmarks.md). Adds what's new; never touches staff
  # entries or ones staff hid.
  def self.seed_from(rows)
    added = 0
    rows.each do |stop_id, klass, kind, name, brand, lat, lon, meters|
      next if name.blank? || SKIP_KINDS.include?(kind) || (klass == "building" && kind == "yes")
      next if where(stop_id: stop_id).where("lower(name) = ?", name.downcase).exists?
      create!(stop_id: stop_id, name: name, kind: kind, lat: lat, lon: lon, meters: meters.to_i, brand: brand.present?, source: "map")
      added += 1
    end
    added
  end

  def as_json(*)
    { id: id, name: name, kind: kind, lat: lat&.to_f, lon: lon&.to_f, meters: meters, source: source }
  end
end
