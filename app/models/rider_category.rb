# Fixed-route rider category for walk-on counts (Adult, Senior, Student...).
# A lookup table, editable under Lookup Tables; hidden per provider like the
# others.
class RiderCategory < ApplicationRecord
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
    { id: id, name: name, default_fare: default_fare.to_f }
  end
end
