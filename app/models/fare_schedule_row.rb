# One cell of a provider's distance-band fare table: for trips of up to
# up_to_miles (nil = any longer trip), a rider in this category pays fare.
# FareSchedule reads the table; the office edits it as a grid on the
# provider's fare settings page.
class FareScheduleRow < ApplicationRecord
  has_paper_trail

  SERVICES = %w[demand_response commuter].freeze

  belongs_to :provider
  belongs_to :rider_category

  validates :service, inclusion: { in: SERVICES }
  validates :fare, numericality: { greater_than_or_equal_to: 0 }
  validates :up_to_miles, numericality: { greater_than: 0 }, allow_nil: true
  validates :rider_category_id, uniqueness: { scope: [:provider_id, :service, :up_to_miles] }

  scope :for_provider, -> (provider_id) { where(provider_id: provider_id) }
  scope :for_service,  -> (service) { where(service: service) }
  # Bands in order, the open-ended one last.
  scope :by_band,      -> { order(Arel.sql("up_to_miles IS NULL, up_to_miles"), :rider_category_id) }

  def band_label
    up_to_miles.nil? ? "over #{self.class.previous_edge_label(self)}" : "up to #{format_miles(up_to_miles)} mi"
  end

  private

  def format_miles(m)
    m.to_f == m.to_i ? m.to_i.to_s : m.to_f.to_s
  end

  def self.previous_edge_label(row)
    prev = for_provider(row.provider_id).for_service(row.service).where.not(up_to_miles: nil).maximum(:up_to_miles)
    prev.nil? ? "0" : (prev.to_f == prev.to_i ? prev.to_i.to_s : prev.to_f.to_s) + " mi"
  end
end
