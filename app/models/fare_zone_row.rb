# One cell of a county's destination fare (Jackson and Matagorda price a trip
# by where it goes, not how far): a rider in this category pays fare for a
# trip in this zone. FareSchedule reads these ahead of any distance table.
#
#   town          both ends in place (Edna, Bay City)
#   county        both ends in the county
#   other_county  the far end in another county GCRPC serves
#   city          the far end in place (Houston, Corpus Christi ...)
class FareZoneRow < ApplicationRecord
  has_paper_trail

  ZONES = %w[town county other_county city].freeze

  belongs_to :provider
  belongs_to :rider_category

  validates :county, presence: true
  validates :zone, inclusion: { in: ZONES }
  validates :place, presence: true, if: -> { zone.in?(%w[town city]) }
  validates :fare, numericality: { greater_than_or_equal_to: 0 }

  scope :for_provider, -> (provider_id) { where(provider_id: provider_id) }
  scope :for_county,   -> (county) { where("lower(county) = ?", county.to_s.strip.downcase) }
end
