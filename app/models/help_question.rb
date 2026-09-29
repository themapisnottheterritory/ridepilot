# One question to Ask RidePilot (the help panel) and its answer.
class HelpQuestion < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :provider, optional: true

  validates :question, presence: true

  scope :recent, -> { order(created_at: :desc) }
end
