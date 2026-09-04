# Fixed-route fare type for walk-ons (Cash, Pass, Free / Transfer...). A lookup
# table, editable under Lookup Tables; hidden per provider like the others.
class FareType < ApplicationRecord
  acts_as_paranoid
  has_paper_trail

  has_many :boardings, class_name: "FixedRouteBoarding"

  validates :name, presence: true, uniqueness: { case_sensitive: false, conditions: -> { where(deleted_at: nil) } }

  scope :default_order, -> { order(:id) }

  def self.by_provider(provider)
    hidden_ids = HiddenLookupTableValue.hidden_ids self.table_name, provider.try(:id)
    where.not(id: hidden_ids)
  end

  def as_api_json
    { id: id, name: name, fare_factor: fare_factor.to_f }
  end
end
