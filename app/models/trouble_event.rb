# One moment where RidePilot got in someone's way (TroubleWatch records them,
# TroubleBoard shows them). Counted by screen and agency, never by person.
class TroubleEvent < ApplicationRecord
  KINDS = %w[error message slow].freeze
  KEEP = 90.days

  validates :kind, inclusion: { in: KINDS }

  scope :since, ->(time) { where("trouble_events.created_at >= ?", time) }

  # digits out (ids, times, amounts) so the same trouble groups together;
  # short, so a message can't carry much with it
  def self.scrub(text)
    text.to_s.squish.gsub(/\d+/, "#").truncate(240)
  end

  def self.prune!
    where("created_at < ?", KEEP.ago).delete_all
  end
end
