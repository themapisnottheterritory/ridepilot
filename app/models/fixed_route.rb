# A fixed route as operated: "Red" (both directions), "Bay" (the Inteplast
# commuter). Drawn in the fixed-route authoring tool, synced here by
# `rake fixed_routes:sync`; RidePilot is where it is run. A fixed-mode Run
# points at one of these for the day.
class FixedRoute < ApplicationRecord
  acts_as_paranoid
  has_paper_trail

  KINDS = %w[city commuter].freeze

  # A city one-bus block as a route of its own, so a day when one driver runs
  # Gold then Green shows as "Gold+Green" in the lineup like the commuter
  # doubles (Bay+Pal ...). Unlike those, it is not in the authoring tool: the
  # bus drives the parts' own loops and the tablet flips between them (block
  # 4-5_C1, gcrpc-fixedroute/ops/one-bus-combo.md), and a merged route there
  # would show riders a phantom route. So RidePilot builds it from its parts
  # (external_route_ids = theirs, see .rebuild_combos!) and it owns no stops:
  # operating_stops are the parts' own rows, which keeps boardings credited to
  # Gold and Green.
  COMBOS = { "Gold+Green" => %w[Gold Green] }.freeze

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
  def combo?;    COMBOS.key?(name);  end

  # The routes a combo is made of, in driving order; [] for an ordinary route.
  def combo_parts
    return [] unless combo?
    parts = FixedRoute.for_provider(provider_id).where(name: COMBOS[name]).index_by(&:name)
    COMBOS[name].filter_map { |n| parts[n] }
  end

  # The stops a bus on this route serves: its own, or for a combo its parts'.
  def operating_stops
    return stops unless combo?
    ids = combo_parts.map(&:id)
    return FixedRouteStop.none if ids.empty?
    part_order = ids.each_with_index.map { |id, i| "WHEN #{id.to_i} THEN #{i}" }.join(" ")   # Postgres 9.4: no array_position
    FixedRouteStop.where(fixed_route_id: ids)
                  .order(Arel.sql("CASE fixed_route_stops.fixed_route_id #{part_order} END"), :direction, :sequence)
  end

  # Stop directions in operating order ("East", "West").
  def directions
    operating_stops.map(&:direction).uniq
  end

  # Create or refresh each combo from its parts: kind and color of the first
  # part, route ids of all of them. Run after fixed_routes:sync.
  def self.rebuild_combos!(provider)
    COMBOS.filter_map do |name, part_names|
      parts = for_provider(provider.id).active.where(name: part_names).index_by(&:name)
      next if part_names.any? { |n| parts[n].nil? }
      ordered = part_names.map { |n| parts[n] }
      combo = for_provider(provider.id).find_or_initialize_by(name: name)
      combo.assign_attributes(kind: ordered.first.kind, color: ordered.first.color, active: true,
                              short_name: ordered.map(&:short_name).compact.join("+").presence,
                              external_route_ids: ordered.flat_map(&:external_route_ids))
      combo.save!
      combo
    end
  end

  def css_color
    "##{color}" if color.present?
  end

  def display_name
    commuter? ? "#{name} (commuter)" : name
  end
end
