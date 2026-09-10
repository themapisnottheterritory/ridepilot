# One line in a rider's fare ledger. Append only: a row is never edited or
# deleted, a mistake is corrected with a further adjust or refund row, so the
# ledger always explains customers.fare_balance. Create rows through
# FareLedger, which takes the customer lock and keeps balance_after right.
class FareTransaction < ApplicationRecord
  KINDS = %w[load debit refund adjust transfer_in transfer_out].freeze
  PAYMENT_METHODS = %w[cash check card_online].freeze
  PAYMENT_LABELS = { "cash" => "Cash", "check" => "Check", "card_online" => "Card / online" }.freeze

  belongs_to :provider
  belongs_to :customer
  belongs_to :fare_token, optional: true
  belongs_to :recorded_by, class_name: "User", foreign_key: :recorded_by_user_id, optional: true
  belongs_to :driver, optional: true
  belongs_to :run, optional: true
  belongs_to :trip, optional: true
  belongs_to :fixed_route_boarding, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :amount, numericality: { other_than: 0 }
  validates :balance_after, :recorded_at, :client_uuid, presence: true
  validates :payment_method, inclusion: { in: PAYMENT_METHODS }, if: -> { kind == "load" }
  validates :payment_method, absence: true, unless: -> { kind == "load" }
  validates :note, presence: true, if: -> { kind == "adjust" }
  validate  :sign_matches_kind

  scope :for_provider,  -> (provider_id) { where(provider_id: provider_id) }
  scope :chronological, -> { order(:recorded_at, :id) }
  scope :newest_first,  -> { order(recorded_at: :desc, id: :desc) }
  scope :loads,         -> { where(kind: "load") }
  scope :recorded_between, -> (from, to) { where(recorded_at: from...to) }

  def readonly?
    persisted?
  end

  def load?;   kind == "load";   end
  def debit?;  kind == "debit";  end

  def kind_label
    { "load" => "Load", "debit" => "Fare", "refund" => "Refund", "adjust" => "Adjustment",
      "transfer_in" => "Transfer in", "transfer_out" => "Transfer out" }[kind] || kind
  end

  def payment_label
    PAYMENT_LABELS[payment_method]
  end

  private

  def sign_matches_kind
    return if amount.nil? || amount.zero?
    case kind
    when "load", "refund", "transfer_in"
      errors.add(:amount, "must be positive for a #{kind_label.downcase}") if amount < 0
    when "debit", "transfer_out"
      errors.add(:amount, "must be negative for a #{kind_label.downcase}") if amount > 0
    end
  end
end
