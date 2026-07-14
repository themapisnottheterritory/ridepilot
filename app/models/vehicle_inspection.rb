class VehicleInspection < ApplicationRecord
  acts_as_paranoid # soft delete
  has_paper_trail

  belongs_to :provider

  validates_presence_of :description

  scope :across_system,       -> { where(provider_id: nil) }
  scope :provider_specific,   ->(provider_id) { where(provider_id: provider_id) }

  scope :for_phase, ->(p) { where(phase: [p.to_s, "both"]) }
  scope :ordered,   -> { order(:position, :id) }
  # `cdl_only` items (air brakes, slack adjuster, compressor) are intended to show
  # only for air-brake / CDL vehicle types — wire that filter in the API (step 2).

  def self.by_provider(provider)
    hidden_ids = HiddenLookupTableValue.hidden_ids self.table_name, provider.try(:id)
    where.not(id: hidden_ids).where("provider_id is NULL or provider_id = ?", provider.try(:id))
  end
end
