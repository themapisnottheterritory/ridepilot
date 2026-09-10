# Something a rider presents at the door that identifies their customer
# record: an RFID card (its factory UID), a printed QR code, or later a
# bank-card reference. The token carries no value; the balance is on the
# customer (docs/fare-card-design.md, section 4).
#
# uid is stored in one canonical form (separators removed, upcased) so the
# office reader and the bus reader match even if one types "04 a3 b2" and the
# other "04A3B2". Readers can be set to hex or decimal; lookup tries both.
class FareToken < ApplicationRecord
  acts_as_paranoid
  has_paper_trail

  KINDS    = %w[rfid qr bank_card_ref].freeze
  STATUSES = %w[active lost blocked retired].freeze

  belongs_to :provider
  belongs_to :customer
  belongs_to :issued_by, class_name: "User", foreign_key: :issued_by_user_id, optional: true
  has_many   :fare_transactions

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :uid, presence: true, uniqueness: { conditions: -> { where(deleted_at: nil) }, message: "is already issued to another rider" }
  validates :serial, uniqueness: { scope: :provider_id, conditions: -> { where(deleted_at: nil) }, allow_blank: true }
  validate  :customer_belongs_to_provider

  before_validation :normalize_uid
  before_validation :fill_qr_uid, on: :create
  before_validation :fill_serial, on: :create
  before_validation :fill_issued_at, on: :create

  scope :for_provider,  -> (provider_id) { where(provider_id: provider_id) }
  scope :active,        -> { where(status: "active") }
  scope :default_order, -> { order(:status, :issued_at, :id) }

  def self.normalize_uid(raw)
    raw.to_s.gsub(/[\s:\-]/, "").upcase
  end

  # Resolve what a reader typed. Tries the canonical form, then the other
  # radix in case the office reader is set to decimal and the bus reader to
  # hex (or the reverse). A serial number is not tried here; see
  # FareAccountsController#lookup.
  def self.lookup(raw)
    uid = normalize_uid(raw)
    return nil if uid.blank?
    candidates = [uid]
    if uid =~ /\A\d+\z/ && uid.length <= 20
      hex = uid.to_i.to_s(16).upcase
      hex = "0" + hex if hex.length.odd?
      candidates += [hex, hex.rjust(8, "0"), hex.rjust(14, "0")]   # 4-byte and 7-byte UIDs, zero padded
    end
    if uid =~ /\A[0-9A-F]+\z/ && uid.length <= 16
      dec = uid.to_i(16).to_s
      candidates += [dec, dec.rjust(10, "0")]                      # EM4100-style 10-digit decimal
    end
    candidates.uniq.each do |c|
      t = find_by(uid: c)
      return t if t
    end
    nil
  end

  def active?;  status == "active"; end
  def usable?;  active? && customer && customer.active?; end

  def kind_label
    { "rfid" => "RFID card", "qr" => "QR code", "bank_card_ref" => "Bank card" }[kind] || kind
  end

  def display_uid
    kind == "rfid" ? uid.scan(/.{1,2}/).join(" ") : uid
  end

  def label
    serial.present? ? "##{serial}" : display_uid
  end

  private

  def normalize_uid
    self.uid = self.class.normalize_uid(uid) if uid.present?
    self.serial = serial.to_s.strip.presence
  end

  # A QR token has no factory id, so we mint one: 12 chars, no vowels so it
  # never spells anything, and never starting with a digit so it cannot be
  # mistaken for a decimal UID.
  def fill_qr_uid
    return unless kind == "qr" && uid.blank?
    alphabet = %w[B C D F G H J K L M N P Q R S T V W X Z 2 3 4 5 6 7 8 9]
    loop do
      candidate = (alphabet - %w[2 3 4 5 6 7 8 9]).sample + Array.new(11) { alphabet.sample }.join
      unless self.class.with_deleted.exists?(uid: candidate)
        self.uid = candidate
        break
      end
    end
  end

  # The printed number on the card. If the office does not type one we take
  # the next number for the provider so every token has a short human handle.
  def fill_serial
    return if serial.present? || provider_id.nil?
    last = self.class.with_deleted.where(provider_id: provider_id).where("serial ~ '^[0-9]+$'")
                     .pluck(:serial).map(&:to_i).max || 1000
    self.serial = (last + 1).to_s
  end

  def fill_issued_at
    self.issued_at ||= Time.current
  end

  def customer_belongs_to_provider
    return if customer.nil? || provider_id.nil?
    unless Customer.for_provider(provider_id).where(id: customer_id).exists?
      errors.add(:customer, "is not a rider with this provider")
    end
  end
end
