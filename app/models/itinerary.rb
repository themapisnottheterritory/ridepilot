class Itinerary < ApplicationRecord
  include ItineraryCore

  acts_as_paranoid # soft delete
  
  belongs_to :trip, optional: true  # run begin/end legs have no trip (Rails 7 belongs_to is required by default)
  belongs_to :run
  has_one :public_itinerary

  scope :finished, -> { where.not(finish_time: nil) }

  # STATUS CODE
  # 0 - Pending
  # 1 - In Progress
  # 2 - Completed
  # 3 - Done with exceptions: No Show etc
  STATUS_PENDING = 0
  STATUS_IN_PROGRESS = 1
  STATUS_COMPLETED = 2
  STATUS_OTHER = 3

  # get associated fare info from trip
  def fare
    trip = self.trip
    if trip 
      trip_fare = trip.fare || trip.provider.fare
      if trip_fare && !trip_fare.is_free? && (
          (trip_fare.pre_trip && self.is_pickup?) ||
          (!trip_fare.pre_trip && self.is_dropoff?)
        )

        trip_fare
      else
        nil
      end
    else 
      nil
    end
  end

  def copyAvlDataFrom!(a_itin)
    self.status_code = a_itin.status_code
    self.departure_time = a_itin.departure_time
    self.arrival_time = a_itin.arrival_time
    self.finish_time = a_itin.finish_time
    self.save(validate: false)
  end

  def reset!
    self.status_code = nil
    self.departure_time = nil
    self.arrival_time = nil
    self.finish_time = nil
    self.save(validate: false)
  end
end