# A staff decision on Pins to check: moved the pin to where drivers stop, or kept it.
class PinCheck < ActiveRecord::Base
  belongs_to :address, -> { with_deleted }, optional: true
  belongs_to :user, optional: true
  DECISIONS = %w[moved kept].freeze
  validates :decision, inclusion: { in: DECISIONS }
end
