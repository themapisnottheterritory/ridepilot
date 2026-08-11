class CustomerRidershipMobility < RidershipMobilityMapping
  belongs_to :customer, foreign_key: :host_id, optional: true
end
