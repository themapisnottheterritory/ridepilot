# A customer's recent and coming trips, for the Trips panel on the customer's
# page (last 10 and next 10 together) and the hover card on their name.
#
#   CustomerTrips.new(customer).recent   # latest first
#   CustomerTrips.new(customer).coming   # soonest first
class CustomerTrips
  SHOW = 10

  def initialize(customer, now: Time.current)
    @customer, @now = customer, now
  end

  def recent(limit = SHOW)
    base.where("trips.pickup_time < ?", @now).reorder(pickup_time: :desc).limit(limit)
  end

  def coming(limit = SHOW)
    base.where("trips.pickup_time >= ?", @now).reorder(pickup_time: :asc).limit(limit)
  end

  def last_and_next
    [recent(1).first, coming(1).first]
  end

  private

  def base
    Trip.where(customer_id: @customer.id).includes(:pickup_address, :dropoff_address, :trip_result, :run)
  end
end
