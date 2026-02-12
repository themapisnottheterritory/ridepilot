class Ethnicity < ApplicationRecord
  acts_as_paranoid # soft delete
  has_paper_trail

  validates :name, presence: true, length: { minimum: 2 }, uniqueness: {case_sensitive: false, conditions: -> { where(deleted_at: nil) } }

  default_scope { order('name') }

  def self.by_provider(provider)
    hidden_ids = HiddenLookupTableValue.hidden_ids self.table_name, provider.try(:id)
    where.not(id: hidden_ids)
  end
end
