# One finished pickup or drop-off, and where the van sat still for it (DriverStops).
class StopSighting < ActiveRecord::Base
  belongs_to :address, -> { with_deleted }, optional: true
end
