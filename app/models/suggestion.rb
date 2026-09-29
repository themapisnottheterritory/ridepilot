# Send a suggestion: ideas, problems and questions staff send to GCRPC I.T.
# (SuggestionsController, SuggestionMailer). The sender chose to send it, so
# their name goes with it; they see its status and I.T.'s reply under
# "Your suggestions". I.T. (system admins) sees every agency's; an agency's
# admins see their own agency's.
class Suggestion < ApplicationRecord
  belongs_to :user
  belongs_to :provider, optional: true
  belongs_to :help_question, optional: true
  belongs_to :replied_by, class_name: "User", optional: true

  KINDS = {
    "idea"     => "An idea or suggestion",
    "problem"  => "Something isn't working",
    "question" => "A question"
  }.freeze
  STATUSES = {
    "new"         => "New",
    "planned"     => "Planned",
    "done"        => "Done",
    "not_planned" => "Not planned"
  }.freeze

  validates :body, presence: true, length: { maximum: 4000 }
  validates :kind, inclusion: { in: KINDS.keys }
  validates :status, inclusion: { in: STATUSES.keys }

  scope :newest_first, -> { order(created_at: :desc) }

  # Off until staff know the designed workflows (Philz, 2026-09-29): no links
  # show and the pages answer 404. SUGGESTIONS_ENABLED=true turns it on.
  def self.enabled?
    ENV["SUGGESTIONS_ENABLED"] == "true"
  end

  def self.visible_to(user, provider)
    return all if user.super_admin?
    return where(provider_id: provider&.id) if user.admin?
    where(user_id: user.id)
  end

  def self.manageable_by?(user)
    user.admin?
  end

  def kind_label
    KINDS[kind]
  end

  def status_label
    STATUSES[status]
  end

  # "Dispatch", "Trips", ... from the page it was sent from
  def screen
    TroubleWatch.screen_for_path(page_path)
  end
end
