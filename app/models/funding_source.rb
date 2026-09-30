class FundingSource < ApplicationRecord
  acts_as_paranoid # soft delete
  has_paper_trail

  validates_presence_of :name
  validates_length_of :name, minimum: 2
  validate :name_uniqueness

  scope :across_system,       -> { where(provider_id: nil) }
  scope :provider_specific,   ->(provider_id) { where(provider_id: provider_id) }
  scope :ntd_reportable,      -> { where(ntd_reportable: true) }

  SHOW_ALL_ID = -1

  # no_fare: the funding source pays for the whole ride and the rider pays
  # nothing (e.g. Lavaca's Title III riders, billed to New Horizons monthly).
  # The office quotes no fare, the manifest says so, and the driver's tablet
  # shows no fare box and a NO FARE line on the pickup.
  def no_fare_text
    return nil unless no_fare?
    ["No fare", fare_note.presence].compact.join(": ")
  end

  def driver_note
    return nil unless no_fare?
    "NO FARE: #{fare_note.presence || "paid by #{name}"}. Don't collect a fare."
  end

  def self.by_provider(provider)
    hidden_ids = HiddenLookupTableValue.hidden_ids self.table_name, provider.try(:id)
    where.not(id: hidden_ids).where("provider_id is NULL or provider_id = ?", provider.try(:id))
  end

  private

  def name_uniqueness
    if FundingSource.where("deleted_at is NULL and lower(name) = ? and (provider_id is NULL or provider_id = ?)", name.try(:downcase), provider_id).any?
      errors.add(:base, "Name has already been taken")
    end
  end
end
