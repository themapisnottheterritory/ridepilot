class CustomerAuth < ApplicationRecord
  belongs_to :customer

  before_create :generate_token

  scope :active, -> { where("expires_at > ?", Time.current) }

  def self.generate_for(customer, expires_in: 7.days)
    create!(customer: customer, expires_at: expires_in.from_now)
  end

  def expired?
    expires_at < Time.current
  end

  private

  def generate_token
    self.token = SecureRandom.urlsafe_base64(32)
  end
end
