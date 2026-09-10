# Prices a demand-response trip from the provider's distance-band table
# (docs/fare-card-design.md, section 15).
#
#   FareSchedule.new(provider).price(miles: 7.2, category: senior)   # => 1.00, or nil if no table
#   FareSchedule.new(provider).trip_fare(trip)                        # rider + guests, attendants free
#
# The rider pays their category's fare for the band the trip's drive
# distance falls in. Each guest pays the Adult fare for the same band.
# Attendants (personal care assistants) ride free. Returns nil when the
# provider has no rows for the service or the trip has no distance, so
# callers can fall through to the flat default.
class FareSchedule
  attr_reader :provider, :service

  def initialize(provider, service: "demand_response")
    @provider = provider
    @service = service
  end

  def rows
    @rows ||= FareScheduleRow.for_provider(provider.id).for_service(service).includes(:rider_category).by_band.to_a
  end

  def configured?
    rows.any?
  end

  def bands
    rows.map(&:up_to_miles).uniq
  end

  def price(miles:, category:)
    return nil unless configured? && category
    m = BigDecimal(miles.to_s)
    band = bands.find { |edge| edge.nil? || m <= edge }
    row = rows.find { |r| r.up_to_miles == band && r.rider_category_id == category.id }
    row&.fare
  end

  # The whole fare for a trip: rider plus guests. nil if it cannot be priced.
  def trip_fare(trip, category: nil)
    return nil unless configured? && trip.drive_distance.to_f > 0
    category ||= category_for(trip.customer)
    rider = price(miles: trip.drive_distance, category: category)
    return nil if rider.nil?
    guests = trip.guest_count.to_i
    guest_fare = guests > 0 ? (price(miles: trip.drive_distance, category: adult_category) || rider) : 0
    (rider + guest_fare * guests).round(2)
  end

  def category_for(customer)
    visible = RiderCategory.by_provider(provider)
    (customer&.default_rider_category_id && visible.find_by(id: customer.default_rider_category_id)) || visible.default_order.first
  end

  def adult_category
    @adult ||= RiderCategory.by_provider(provider).where("lower(name) = 'adult'").first || RiderCategory.by_provider(provider).default_order.first
  end

  # Replace the table for this service from a grid of { up_to_miles => { rider_category_id => fare } }.
  # A blank edge is the open-ended band. Blank cells are $0.00 (free).
  def replace!(grid, by: nil)
    FareScheduleRow.transaction do
      PaperTrail.request(whodunnit: by&.id.to_s.presence) do
        FareScheduleRow.for_provider(provider.id).for_service(service).destroy_all
        grid.each do |edge, cells|
          edge_val = edge.to_s.strip.presence && BigDecimal(edge.to_s)
          cells.each do |category_id, fare|
            FareScheduleRow.create!(provider: provider, service: service, up_to_miles: edge_val,
                                    rider_category_id: category_id, fare: (BigDecimal(fare.to_s.gsub(/[$,\s]/, "")) rescue 0))
          end
        end
      end
    end
    @rows = nil
    self
  end
end
