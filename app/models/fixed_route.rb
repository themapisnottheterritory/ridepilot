# A fixed route as operated: "Red" (both directions), "Bay" (the Inteplast
# commuter). Drawn in the fixed-route authoring tool, synced here by
# `rake fixed_routes:sync`; RidePilot is where it is run. A fixed-mode Run
# points at one of these for the day.
class FixedRoute < ApplicationRecord
  acts_as_paranoid
  has_paper_trail

  KINDS = %w[city commuter].freeze

  belongs_to :provider
  has_many :stops, -> { order(:direction, :sequence) }, class_name: "FixedRouteStop", dependent: :destroy
  has_many :runs
  has_many :repeating_runs
  has_many :boardings, class_name: "FixedRouteBoarding"

  validates :name, presence: true, uniqueness: { case_sensitive: false, scope: :provider_id, conditions: -> { where(deleted_at: nil) } }
  validates :kind, inclusion: { in: KINDS }
  validates :color, format: { with: /\A[0-9A-Fa-f]{6}\z/, allow_blank: true }

  scope :active,       -> { where(active: true) }
  scope :for_provider, -> (provider_id) { where(provider_id: provider_id) }
  scope :default_order, -> { order(:kind, :name) }

  def city?;     kind == "city";     end
  def commuter?; kind == "commuter"; end

  # Stop directions in operating order ("East", "West").
  def directions
    stops.map(&:direction).uniq
  end

  def css_color
    "##{color}" if color.present?
  end

  def display_name
    commuter? ? "#{name} (commuter)" : name
  end
end
